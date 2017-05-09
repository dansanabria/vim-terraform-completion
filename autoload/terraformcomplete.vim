if !has("ruby") && !has("ruby/dyn")
    finish
endif

if exists('g:syntastic_extra_filetypes')
    call add(g:syntastic_extra_filetypes, 'terraform')
else
    let g:syntastic_extra_filetypes = ['terraform']
endif


if !exists('g:terraformcomplete_version')
  ruby <<EOF
    ENV['PATH'].split(':').each do |folder|
        if File.exists?(folder+'/terraform')
            Vim::command("let g:terraformcomplete_version = '#{`terraform -v`.match(/v(.*)/).captures[0]}'")

        else
            Vim::command("let g:terraformcomplete_version = '0.9.4'")
        end
    end
EOF
endif

let s:path = fnamemodify(resolve(expand('<sfile>:p')), ':h')

if !exists('g:terraform_docs_versions')
    let g:terraform_docs_versions = []
    for s:version in split(globpath(s:path . '/../provider_json', "**/"), '\n')
        let g:terraform_docs_versions += split(split(s:version, s:path . '/../provider_json/')[-1], '/')
    endfor
endif







let s:oldpos = []
function! terraformcomplete#JumpRef()
    try 
        let old_pos = getpos(".")
        if strpart(getline("."),0, getpos(".")[2]) =~ ".*{"
            execute 'normal! t}'
            let a:curr = strpart(getline("."),0, getpos(".")[2])
            let a:attr = split(split(a:curr, "${")[-1], '\.')
            call setpos('.', old_pos)
            let s:oldpos = getpos('.')

            if a:attr[0] == 'var'
                call search('\s*variable\s*"' . a:attr[1] . '".*')
            else
                call search('.*\s*"' . a:attr[0] . '"\s*"' . a:attr[1] . '".*')
            end
            echo 'Jump to ' . a:attr[0] . '.' . a:attr[1]
        else
            call setpos('.', s:oldpos)
            echo 'Jumping Back'
            let s:oldpos = []
        end
    catch
    endtry
endfunction

function! terraformcomplete#GetDoc()
    let s:curr_pos = getpos('.')
    if getline(".") !~# '^\s*\(resource\|data\)\s*"'
        execute '?\s*\(resource\|data\)\s*"'
    endif
    let a:provider = split(split(substitute(getline("."),'"', '', ''))[1], "_")[0]

    let a:resource = substitute(split(split(getline("."))[1], a:provider . "_")[1], '"','','')
    if getline(".") =~ '^data.*'
        let s:type = 'datas'
    else
        let s:type = 'resources'
    end
    call setpos('.', s:curr_pos)

    let res = system(s:path . '/../utils/get_doc ' . s:path . ' ' . expand("<cWORD>") . " " . a:provider . " " . a:resource . " " . s:type)

    echo substitute(res, '\n', '', '')
endfunction


fun! terraformcomplete#GetResource()
    let s:curr_pos = getpos('.')
    if getline(".") !~# '^\s*\(resource\|data\)\s*"'
        execute '?\s*\(resource\|data\)\s*"'
    endif
    let a:provider = split(split(substitute(getline("."),'"', '', ''))[1], "_")[0]

    let a:resource = substitute(split(split(getline("."))[1], a:provider . "_")[1], '"','','')
    call setpos('.', s:curr_pos)
    unlet s:curr_pos
    return a:resource
endfun

fun! terraformcomplete#GetProvider()
    let s:curr_pos = getpos('.')
    if getline(".") !~# '^\s*\(resource\|data\)\s*"'
        execute '?\s*\(resource\|data\)\s*"'
    endif

    let a:provider = split(split(substitute(getline("."),'"', '', ''))[1], "_")[0]

    call setpos(".", s:curr_pos)
    unlet s:curr_pos
	return a:provider
endfun

function! terraformcomplete#rubyComplete(ins, provider, resource, attribute, data_or_resource)
    let s:curr_pos = getpos('.')
    let a:res = []
    let a:resource_line = getline(s:curr_pos[1]) =~ "^\s*resource"
    let a:data_line = getline(s:curr_pos[1]) =~ "^\s*data"
    let a:provider_line = (strpart(getline("."),0, getpos(".")[2]) =~ '^\s*\(resource\|data\)\s*"\%["]$' || getline(s:curr_pos[1]) =~ "provider")
    

  ruby << EOF
require 'json'

def terraform_complete(provider, resource)
    begin
        data = ''
        if VIM::evaluate('a:provider_line') == 0 then
            File.open("#{VIM::evaluate('s:path')}/../provider_json/#{VIM::evaluate('g:terraformcomplete_version')}/#{provider}.json", "r") do |f|
              f.each_line do |line|
                data = line
              end
            end

            parsed_data = JSON.parse(data)
            if VIM::evaluate('a:attribute') == "true" then
              if VIM::evaluate('a:data_or_resource') == 0 then
                result = parsed_data['datas'][resource]["attributes"]
              else
                result = parsed_data['resources'][resource]["attributes"]
              end
            elsif VIM::evaluate('a:data_line') == 1 then
                temp = parsed_data['datas'].keys
                temp.delete("provider_arguments")
                result = temp.map { |x|
                    { "word" => x }
                }
            elsif VIM::evaluate('a:resource_line') == 1 then
                temp = parsed_data['resources'].keys
                temp.delete("provider_arguments")
                result = temp.map { |x|
                    { "word" => x }
                }
            else
              if VIM::evaluate('a:data_or_resource') == 0 then
                result = parsed_data['datas'][resource]["arguments"]
              else
                result = parsed_data['resources'][resource]["arguments"]
              end
            end
        elsif VIM::evaluate('a:provider_line') == 1 then
            result = Dir.glob("#{VIM::evaluate('s:path')}/../provider_json/#{VIM::evaluate('g:terraformcomplete_version')}/**/*.json").map { |x|
              { "word" => x.split("../provider_json/#{VIM::evaluate('g:terraformcomplete_version')}/")[1].split('.json')[0] }
            }
        end

        return JSON.generate(result)
    rescue
        return []
    end
end


class TerraformComplete
  def initialize()
    @buffer = Vim::Buffer.current
   
    print Vim::evaluate('a:ins')

    result = terraform_complete(VIM::evaluate('a:provider'), VIM::evaluate('a:resource'))
    Vim::command("let a:res = #{result}")
  end
end
gem = TerraformComplete.new()
EOF
let a:resource_line = 0
let a:provider_line = 0
return a:res
endfunction

fun! terraformcomplete#Complete(findstart, base)
  if a:findstart
    " locate the start of the word
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '\a'
      let start -= 1
    endwhile
    return start
  else
    if index(g:terraform_docs_versions, g:terraformcomplete_version) ==? -1
        let g:terraformcomplete_version = '0.9.4'
    endif

    let res = []
    try
      let a:provider = terraformcomplete#GetProvider()
    catch
      let a:provider = ''
    endtry

    try
      let a:resource = terraformcomplete#GetResource()
    catch
      let a:resource = ''
    endtry


    if strpart(getline('.'),0, getpos('.')[2]) =~ '\${[^}]*\%[}]$'
    try
            let a:search_continue = 1
            let a:resource_list = []
            let a:type_list = {}
            let a:data_list = []
            let a:data_type_list = {}

            let a:all_res = terraformcomplete#GetAll('resource')
            let a:resource_list = a:all_res[0]
            let a:type_list = a:all_res[1]
            call add(a:resource_list, { 'word': 'var' })
            call add(a:resource_list, { 'word': 'module' })
            call add(a:resource_list, { 'word': 'data' })

            try
                let a:curr = strpart(getline('.'),0, getpos('.')[2])
                let a:attr = filter(split(split(a:curr, '${')[-1], '\.'), 'v:val !~ "}"')

                if len(a:attr) == 1
                    if a:attr[0] == "data" 
                      let a:data_list = terraformcomplete#GetAll('data')[0]
                      return a:data_list
                    elseif a:attr[0] == "module" 
                      let a:module_list = terraformcomplete#GetAllModule()[0]
                      return a:module_list
                    elseif a:attr[0] == "var" 
                        ruby <<EOF
                        require 'json'

                        def terraform_get_vars()
                            vars_file_path = "#{Vim::evaluate("expand('%:p:h')")}/variables.tf"
                            if File.readable? vars_file_path then
                                vars_array = File.read(vars_file_path)
                                vars_array = vars_array.split("\n")
                                vars_array = vars_array.find_all {|x| x[/variable\s*".*"/]}
                                vars = vars_array.map {|x| { "word": x.split(" ")[1].tr("\"", '')} }
                                return JSON.generate(vars)
                            end
                            return []
                        end

                        Vim::command("let a:vars_res = #{terraform_get_vars()}")
EOF
                        return a:vars_res
                    else
                        if a:type_list != {}
                          return a:type_list[a:attr[0]]
                        else
                          return 
                        endif
                    endif
                elseif len(a:attr) == 2
                    if a:attr[0] == "data" 
                      let a:data_type_list = terraformcomplete#GetAll('data')[1]
                      return a:data_type_list[a:attr[1]]
                    elseif a:attr[0] == "module"
                        let a:file_path = expand('%:p:h')
                        let a:line = terraformcomplete#GetAllModule()[1][a:attr[1]][0]
                        ruby <<EOF
                        require "#{Vim::evaluate("s:path")}/../module"
                        include ModuleUtils
                        line = Vim::evaluate("a:line")
                        file_path = Vim::evaluate("a:file_path")
                        Vim::command("let a:res = #{load_attr_module(line.to_s, file_path)}")
EOF
                        return a:res
                    else
                      let a:provider = split(a:attr[0], "_")[0]

                      let a:resource = split(a:attr[0], a:provider . "_")[0]
                      let a:data_or_resource = 1

                      for m in terraformcomplete#rubyComplete(a:base, a:provider, a:resource, 'true', a:data_or_resource)
                        if m.word =~ '^' . a:base
                          call add(res, m)
                        endif
                      endfor
                      return res
                    endif
                elseif len(a:attr) == 3
                    if a:attr[0] == "data"
                        let a:res = []
                        let a:provider = split(a:attr[1], "_")[0]

                        let a:resource = split(a:attr[1], a:provider . "_")[0]
                        let a:data_or_resource = 0
                        for m in terraformcomplete#rubyComplete(a:base, a:provider, a:resource, 'true', a:data_or_resource)
                            if m.word =~ '^' . a:base
                                call add(a:res, m)
                            endif
                        endfor
                        return a:res
                    endif
                else
                    return a:resource_list
                endif
            catch
                return a:resource_list
            endtry
        catch
            return a:resource_list
        endtry
    else
        try
          let s:curr_pos = getpos('.')
          let s:oldline = getline('.')
          call search('^\s*\(resource\|data\|module\)\s*"', 'b')
          if getline('.') =~ '^\s*module'
            call setpos('.', s:curr_pos)
            let s:curr_pos = getpos('.')
              execute '?\(source\|\module\).*'

              let a:line = getline(".")
              call setpos('.', s:curr_pos)
              if a:line =~ "source"
                  let a:file_path = expand('%:p:h')
              ruby <<EOF
                  require "#{Vim::evaluate("s:path")}/../module"
                  include ModuleUtils
                  line = Vim::evaluate("a:line")
                  file_path = Vim::evaluate("a:file_path")
                  Vim::command("let a:res = #{load_arg_module(line.to_s, file_path)}")
EOF
              return a:res
            endif
          else
            if getline('.') =~ '^\s*data'
              let a:data_or_resource = 0
            else
              let a:data_or_resource = 1
            endif

            call setpos('.', s:curr_pos)
            for m in terraformcomplete#rubyComplete(a:base, a:provider, a:resource, 'false', a:data_or_resource)
              if m.word =~ '^' . a:base
                call add(res, m)
              endif
            endfor
            return res
          endif
      catch
      endtry
    endif
  endif
endfun

fun! terraformcomplete#GetAllModule() abort
  let a:old_pos = getpos('.')
  execute 'normal! gg'
  let a:search_continue = 1
  let a:list = []
  let a:source_list = {}
  if getline(".") =~ 'module\s*".*"\s*' 
      let temp = substitute(split(split(getline(1),'module ')[0], ' ')[0], '"','','g')
      let a:oldpos = getpos('.')
      call search('source\s*=')
      let a:source = getline('.')
      call setpos('.', a:oldpos)
      call add(a:list, { 'word': temp })

      if has_key(a:source_list, temp) == 0
        let a:source_list[temp] = []
      endif

      call add(a:source_list[temp], a:source )
  endif
  while a:search_continue != 0

    let a:search_continue = search('module\s*".*"\s*', 'W')

    if a:search_continue != 0 
      let temp = substitute(split(split(getline(a:search_continue),'module ')[0], ' ')[0], '"','','g')
      let a:oldpos = getpos('.')
      call search('source\s*=')
      let a:source = getline(".")
      call setpos('.', a:oldpos)
      call add(a:list, { 'word': temp })

      if has_key(a:source_list, temp) == 0
        let a:source_list[temp] = []
      endif

      call add(a:source_list[temp], a:source )
    endif
  endwhile
  call setpos('.', a:old_pos)
  return [a:list, a:source_list]
endfunc

fun! terraformcomplete#GetAll(data_or_resource) abort
  let a:old_pos = getpos('.')
  execute 'normal! gg'
  let a:search_continue = 1
  let a:list = []
  let a:type_list = {}
  if getline(".") =~ a:data_or_resource . '\s*"\w*"\s*"[^"]*"' 
      let temp = substitute(split(split(getline(a:search_continue),a:data_or_resource . ' ')[0], ' ')[0], '"','','g')
      call add(a:list, { 'word': temp })

      if has_key(a:type_list, temp) == 0
        let a:type_list[temp] = []
      endif

      call add(a:type_list[temp], { 'word': substitute(split(split(getline(a:search_continue), a:data_or_resource . ' ')[0], ' ')[1], '"','','g')})
  endif
  while a:search_continue != 0

    let a:search_continue = search(a:data_or_resource . '\s*"\w*"\s*"[^"]*"', 'W')

    if a:search_continue != 0 
      let temp = substitute(split(split(getline(a:search_continue),a:data_or_resource . ' ')[0], ' ')[0], '"','','g')
      call add(a:list, { 'word': temp })

      if has_key(a:type_list, temp) == 0
        let a:type_list[temp] = []
      endif

      call add(a:type_list[temp], { 'word': substitute(split(split(getline(a:search_continue), a:data_or_resource . ' ')[0], ' ')[1], '"','','g')})
    endif
  endwhile
  call setpos('.', a:old_pos)
  return [a:list, a:type_list]
endfunc
