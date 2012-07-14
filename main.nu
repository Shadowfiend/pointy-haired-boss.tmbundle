(import Cocoa)

; Filters ANSI escape codes from the given string. Probably nowhere near foolproof.
(function filter-escape-codes (string)
  (/[\003\032]/
    replaceWithString:""
             inString:(/\c[(\[|\(|\))[;?0-9]*[0-9A-Za-z]/
                        replaceWithString:""
                                 inString:string)))

; A PHBTask is used to fire up an NSTask and feed its standard error
; and output to a vico buffer.  Standard input can be written to using
; writeString:, and subclasses can preprocess output
; (preprocessOutput:isError:) or just play with it without modifying the
; resulting output (handleOutput:isError:).
(class PHBTask is NSObject
  (ivar (id) task
        (id) buffer-name
        (id) buffer-text
        (id) std-out
        (id) std-err
        (id) std-in)

  (+ phbTaskWithBufferName:(id)name launchPath:(id)launchPath isShellScript:(BOOL)runInShell is
    (((PHBTask) alloc) initWithBufferName:name launchPath:launchPath isShellScript:runInShell))

  (- initWithBufferName:(id)name launchPath:(id)launchPath isShellScript:(BOOL)runInShell is
    (self initWithBufferName:name launchPath:launchPath arguments:'() isShellScript:runInShell))

  (- initWithBufferName:(id)name launchPath:(id)launchPath arguments:(id)argumentList isShellScript:(BOOL)runInShell is
    (self initWithBufferName:name launchPath:launchPath arguments:argumentList workingDirectory:((current-window baseURL) path) isShellScript:runInShell))

  (- initWithBufferName:(id)name launchPath:(id)launchPath arguments:(id)argumentList workingDirectory:(id)workingDirectory isShellScript:(BOOL)runInShell is
    (super init)

    (set @buffer-name name)

    (set @task ((NSTask alloc) init))
    (let ((std-out-pipe (NSPipe pipe))
          (std-err-pipe (NSPipe pipe))
          (std-in-pipe (NSPipe pipe))
          (current-window (current-window)))
      (set @std-out (std-out-pipe fileHandleForReading))
      (set @std-err (std-err-pipe fileHandleForReading))
      (set @std-in (std-in-pipe fileHandleForWriting))

      (if runInShell
        (then
          (@task setLaunchPath:"/bin/bash")
          (@task setArguments:(NSArray arrayWithList:(cons launchPath argumentList))))
        (else
          (@task setLaunchPath:launchPath)))

      (@task setCurrentDirectoryPath:workingDirectory)
      (@task setStandardInput:std-in-pipe)
      (@task setStandardOutput:std-out-pipe)
      (@task setStandardError:std-err-pipe)
      
      ((NSNotificationCenter defaultCenter)
        addObserver:self
           selector:"outputReceived:"
               name:NSFileHandleReadCompletionNotification
             object:nil))
    self)

  (- start is
    ((current-text) input:(+ "<esc>:tabnew " @buffer-name "<CR>"))
    (set @buffer-text (current-text))
    (@buffer-text input:"<esc>gT")

    (@std-out readInBackgroundAndNotify)
    (@std-err readInBackgroundAndNotify)
    (@task launch))

  (- exit is
    (@buffer-text input:"<esc>:bd<CR>")
    (@task terminate))

  (- forceExit is
    (system (+ "kill -9 " (@task processIdentifier))))

  (- writeString:(id)aString is
    (@std-in writeData:(aString dataUsingEncoding:NSUTF8StringEncoding)))

  (- filterEscapeCodes:(id)aString is
    (filter-escape-codes aString))

  ; For overriding by child classes that want to parse incoming output or whatever.
  (- handleOutput:(id)output isError:(BOOL)isError is)

  ; Does any preprocessing of output before emitting it to the buffer. By default,
  ; filters escape codes.
  (- preprocessOutput:(id)output isError:(BOOL)isError is
    (filter-escape-codes output))

  (- appendOutput:(id)output is
    (let (text-storage (@buffer-text textStorage))
      (let (line-range (text-storage rangeOfLine:(text-storage lineCount)))
        (let (line-end (+ (head line-range) (head (tail line-range))))
          (@buffer-text insertString:output atLocation:line-end)))))

  (- outputReceived:(id) notification is
    (if (or (eq (notification object) @std-out) (eq (notification object) @std-err))
      (let ((isError (eq (notification object) @std-err))
          (data ((notification userInfo) objectForKey:NSFileHandleNotificationDataItem)))
        (let (string-data ((NSString alloc) initWithData:data encoding:NSUTF8StringEncoding))
          (self handleOutput:string-data isError:isError)
          (self appendOutput:(self preprocessOutput:string-data isError:isError)))

        ; 0-length data means we are at EOF.
        (unless (<= (data length) 0)
          ((notification object) readInBackgroundAndNotify)))))
          
  (- dealloc is
    (@task terminate)
    ((NSNotificationCenter) defaultCenter) removeObserver:self))

