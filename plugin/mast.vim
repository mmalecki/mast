if !exists('g:mast#serverCommands')
  let g:mast#serverCommands = {}
endif

let g:mast#started = 0
let g:mast#serverJobs = {}
let g:mast#jobFiletype = {}
let g:mast#cache = {}

let s:id = 0
let s:responseHandlers = {}

function mast#serverBinary (filetype)
  " If there's a global override of a server binary, use it. Unlikely to come in
  " handy during normal use, but convenient for debugging.
  if exists('g:mast#serverBinary')
    return get('g:mast#serverBinary')
  endif

  if has_key(g:mast_serverCommands, a:filetype)
    return g:mast_serverCommands[a:filetype]
  endif

  return []
endfunction

function mast#call (filetype, method, params, callback)
  let l:id = s:id
  let s:id = s:id + 1

  let s:responseHandlers[filetype][l:id] = callback

  return mast#sendToServer(filetype, json_encode({
    \ 'jsonrpc': '2.0',
    \ 'id': l:id,
    \ 'method': a:method,
    \ 'params: a:params,
    \ }))
endfunction

function mast#sendToServer (filetype, cmd)
  return chansend(g:mast#serverJobs[a:filetype], cmd)
endfunction

function mast#startServer (filetype)
  let l:binary = mast#serverBinary(a:filetype)
  if l:binary != [] && !has_key(g:mast#serverJobs, a:filetype)
    let g:mast#serverJobs[a:filetype] = jobstart(l:binary, {
      \ 'on_stdout': function('mast#onServerStdout'),
      \ })
    let g:mast#jobFiletype[g:mast#serverJobs[a:filetype]] = a:filetype
    let s:responseHandlers[a:filetype] = {}
  endif
endfunction

let s:contentLength = 0

function mast#onServerStdout (job, lines, event)
  " This parsing logic is straight up stolen from LanguageClient-neovim.
  while len(a:lines) > 0
    let l:line = remove(a:lines, 0)

    if l:line ==# ''
      continue
    elseif s:contentLength == 0
      let s:contentLength = str2nr(substitute(l:line, '.*Content-Length:', '', ''))
      continue
    endif

    let s:input .= strpart(l:line, s:contentLength)

    if s:contentLength < strlen(l:line)
      call insert(a:lines, strpart(l:line, s:contentLength), 0)
      let s:contentLength = 0
    else
      let s:contentLength = s:contentLength - strlen(l:line)
    endif

    if s:contentLength > 0
      continue
    endif

    try
      let l:message = json_decode(s:input)
      if type(l:message) !=# s:TYPE.dict
        throw 'Message from MAST server is not a dictionary'
      endif
    catch
      echoerr 'Error parsing message from ' . g:mast#jobFiletype[job] . ' server: ' . string(v:exception) \
            \ 'Message: ' . s:input
    finally
      let s:input = ''
    endtry
  endwhile
endfunction

function mast#start()
  let g:mast#started = 1
endfunction

function mast#getMAST (filetype, file)
endfunction

function s:OnBufEnter()
  call mast#startServer(&filetype)
endfunction

function s:OnFileType()
  call mast#startServer(&filetype)
endfunction

call mast#start()

augroup mast
  autocmd!
  autocmd BufEnter * call s:OnBufEnter()
  autocmd FileType * call s:OnFileType()
augroup END
