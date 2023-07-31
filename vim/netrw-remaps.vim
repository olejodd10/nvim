fun! Netrw_leader_t(islocal) abort
    :normal t
    :tabprevious
endfun

fun! Netrw_leader_b(islocal) abort
    :bdelete
endfun

let g:Netrw_UserMaps = [
    \ ["<leader>t", "Netrw_leader_t"],
    \ ["<leader>b", "Netrw_leader_b"],
    \ ]
