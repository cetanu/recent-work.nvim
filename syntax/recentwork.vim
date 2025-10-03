" highlighting for results buffer
if exists("b:current_syntax")
  finish
endif

syntax match RecentWorkTitle /^Recent Work.*$/
syntax match RecentWorkProjectDir /^Project Directory:.*$/
syntax match RecentWorkAuthorFilter /^Author Filter:.*$/
syntax match RecentWorkSeparator /^=\+$/
syntax match RecentWorkDashes /^-\+$/
syntax match RecentWorkRepo /^📁.*$/
syntax match RecentWorkCommitCount /^\s\+\d\+ recent commits:$/
syntax match RecentWorkBranchAuthorHeader /🌿.*👤.*$/
syntax match RecentWorkCommitLine /^\s\+\w\+\s\+(\d\{4\}-\d\{2\}-\d\{2\}).*$/
syntax match RecentWorkCommitHash /^\s\+\w\+/ contained containedin=RecentWorkCommitLine
syntax match RecentWorkDate /(\d\{4\}-\d\{2\}-\d\{2\})/ contained containedin=RecentWorkCommitLine
syntax match RecentWorkInstruction /^Press.*$/

highlight default link RecentWorkTitle Title
highlight default link RecentWorkProjectDir Identifier
highlight default link RecentWorkAuthorFilter Identifier
highlight default link RecentWorkSeparator Comment
highlight default link RecentWorkDashes Comment
highlight default link RecentWorkRepo Directory
highlight default link RecentWorkCommitCount Number
highlight default link RecentWorkBranchAuthorHeader Type
highlight default link RecentWorkCommitLine Normal
highlight default link RecentWorkCommitHash Constant
highlight default link RecentWorkDate String
highlight default link RecentWorkInstruction Comment

let b:current_syntax = "recentwork"
