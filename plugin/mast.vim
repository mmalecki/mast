if !exists('g:mast#serverCommands')
  let g:mast#serverCommands = {}
endif

let g:mast#started = 0
let g:mast#serverJobs = {}
let g:mast#jobFiletype = {}
let g:mast#cache = {}

let s:id = 0
let s:responseHandlers = {}

let s:TYPE = {
  \ 'dict': type({})
  \ }

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

  let s:responseHandlers[a:filetype][l:id] = a:callback

  return mast#sendToServer(a:filetype, json_encode({
    \ 'jsonrpc': '2.0',
    \ 'id': l:id,
    \ 'method': a:method,
    \ 'params': a:params,
    \ }))
endfunction

function mast#sendToServer (filetype, cmd)
  let l:len = len(a:cmd)
  let l:cmd = "Content-Length: " . l:len . "\r\n\r\n" . a:cmd
  return chansend(g:mast#serverJobs[a:filetype], l:cmd)
endfunction

function mast#startServer (filetype)
  let l:binary = mast#serverBinary(a:filetype)
  echo l:binary
  echo g:mast#serverJobs
  if l:binary != [] && !has_key(g:mast#serverJobs, a:filetype)
    echo 'starting'
    let g:mast#serverJobs[a:filetype] = jobstart(l:binary, {
      \ 'on_stdout': function('s:HandleServerStdout'),
      \ 'on_stderr': function('s:HandleServerStdout'),
      \ })
    let g:mast#jobFiletype[g:mast#serverJobs[a:filetype]] = a:filetype
    let s:responseHandlers[a:filetype] = {}
  endif
endfunction

let s:contentLength = 0
let s:input = ''

function s:HandleServerStdout (job, lines, event) dict abort
  " This parsing logic is straight up stolen from LanguageClient-neovim.
  let l:filetype = g:mast#jobFiletype[a:job]

  while len(a:lines) > 0
    let l:line = remove(a:lines, 0)

    if l:line ==# ''
      continue
    elseif s:contentLength == 0
      let s:contentLength = str2nr(substitute(l:line, '.*Content-Length:', '', ''))
      continue
    endif

    let s:input .= strpart(l:line, 0, s:contentLength + 1)

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
        throw 'Message is not a dictionary'
      endif
    catch
      echoerr 'Error parsing message from ' . l:filetype . ' server: ' . string(v:exception) .
            \ 'Message: ' . s:input
    finally
      let s:input = ''
    endtry

    " For now, we only expect callbacks to our method calls - mAST server has
    " no reason to call methods on our side, because we're sensible people.
    if has_key(l:message, 'result') || has_key(l:message, 'error')
      let l:id = get(l:message, 'id', v:null)

      if l:id is v:null
        echoerr 'Error processing response message from ' . l:filetype . ' server: no request ID. '
             \  'Message: ' . s:input
        continue
      endif

      let l:result = get(l:message, 'result', v:null)
      let l:error = get(l:message, 'error', v:null)

      if l:error
        echoerr 'Error processing request in ' . l:filetype . ' server: ' . get(l:error, 'message', v:null)
             \  'Message: ' . s:input
        continue
      endif

      let l:Handle = get(s:responseHandlers, l:id, v:null)
      call call(l:Handle)
    endif
  endwhile
endfunction

function mast#start()
  let g:mast#started = 1
endfunction

function mast#getMAST (filetype, file)
endfunction

function s:OnBufEnter()
  call mast#startServer(&filetype)

  function! s:astCallback() closure
    echoerr 'got it'
  endfunction

  call mast#call(&filetype, 'textDocument/ast', {
    \ 'textDocument': {
    \   'text': join(getline(1, '$'), "\n")
    \ }
    \ }, funcref('s:astCallback'))
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
