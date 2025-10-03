" highlighting for results buffer
if exists("b:current_syntax")
  finish
endif

syntax match RecentWorkTitle /^Recent Work.*$/
syntax match RecentWorkProjectDir /^Project Directory:.*$/
syntax match RecentWorkSeparator /^=\+$/
syntax match RecentWorkDashes /^-\+$/
syntax match RecentWorkRepo /^📁.*$/
syntax match RecentWorkCommitCount /^\s\+\d\+ recent commits:$/
syntax match RecentWorkCommitHash /🔸\s\+\w\+/
syntax match RecentWorkBranch /\[.*\]/
syntax match RecentWorkDate /(\d\{4\}-\d\{2\}-\d\{2\})/
syntax match RecentWorkAuthor /👤.*$/
syntax match RecentWorkMessage /💬.*$/
syntax match RecentWorkInstruction /^Press.*$/

highlight default link RecentWorkTitle Title
highlight default link RecentWorkProjectDir Identifier
highlight default link RecentWorkSeparator Comment
highlight default link RecentWorkDashes Comment
highlight default link RecentWorkRepo Directory
highlight default link RecentWorkCommitCount Number
highlight default link RecentWorkCommitHash Constant
highlight default link RecentWorkBranch Type
highlight default link RecentWorkDate String
highlight default link RecentWorkAuthor Special
highlight default link RecentWorkMessage Normal
highlight default link RecentWorkInstruction Comment

let b:current_syntax = "recentwork"
