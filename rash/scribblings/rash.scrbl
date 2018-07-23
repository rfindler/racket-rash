#lang scribble/manual

@title[#:tag "rash"]{Rash: The Reckless Racket Shell}
@author+email["William Hatch" "william@hatch.uno"]

@defmodulelang[rash]
@(require
[except-in scribble/eval examples]
scribble/examples
(for-syntax
racket/base
syntax/parse
)
(for-label
rash/prompt-helpers/string-style
racket/contract
rash
(only-in rash/demo/setup in-dir =map= =filter= =foldl=)
(except-in racket/base _ do)
racket/port
racket/splicing
syntax/parse
(prefix-in shell/pipeline-macro/ shell/pipeline-macro)
))

@(define-syntax (irash stx)
   (syntax-parse stx
     [(_ e1 e ...)
      #`(codeblock #:keep-lang-line? #f
                   #,(datum->syntax #'e1 "#lang rash")
                   "\n" e1 e ...)]))

@bold{Rash}, @italic{adj} 1.  Hurrying into action or assertion without due caution and regardless of prudence, hasty, reckless, precipitate.  “@italic{A rash programmer is likely to produce shell scripts.}”

@section{Stability}

Rash is not stable.

But it's getting closer, and it's definitely usable as an interactive shell/repl.

@section{Rash Guide}

Rash is a shell language embedded in Racket.  It has a concrete syntax that is amenable to quick and easy interactions without lots of punctuation overhead.  It aims to allow shell-style interaction and programming to be freely mixed with more general-purpose Racket code.  Like shells you can use it as a day-to-day interface for computing, run programs, wire processes together, etc.  You can copy interactive code into a file and have a working script.  Then you can generalize from there.  However, you have access to all of Racket, its data structures, its libraries, its macro system, and its other DSLs as you make your scripts more general.  Also it allows shell-style process wrangling to be mixed with Racket code, pipelines of functions that pass objects, and much more.  You can gradually move between shell-style Rash code and more normal and general Racket code in different parts of a script, or throw verbatim interactions directly into existing programs as you explore the solution space.

Here follows a quick overview that assumes some knowledge of shell languages like Bash as well as Racket.

Rash can do the sorts of things you expect from shell languages, and a lot of cues for syntax have been taken from traditional Bourne-derived shells.  The following program works as you would expect.@margin-note{Note that Rash is not remotely Posix Shell compliant.}

@codeblock{
#lang rash
cd project-directory
echo How many Racket files do we have?
ls *.rkt | wc -l
}

You can use Racket functions in pipelines.

@irash{
;; This returns the hostname as a string in all caps
cat /etc/hostname |> port->string |> string-upcase
}

Pipelines pass objects.  When a process pipeline segment is next to a function pipeline segment, it passes a port to the function segment.  When a function segment is followed by a process segment, the return value of the function segment is printed to the stdin of the process.

The |>> operator is like the |> operator except that if it receives a port it converts it to a string automatically.  So the above example can be simplified as:

@irash{
cat /etc/hostname |>> string-upcase
}

You can also make pipelines composed entirely of Racket functions.

@irash{
|> directory-list |> map delete-file
}

Pipelines always start with an operator, and if none is specified the @racket[default-pipeline-starter] is inserted.  Pipeline operators are user-definable with @racket[define-pipeline-operator].  Defining new operators can help make common patterns shorter, simpler, and flatter.  For instance the @racket[=map=] operator wraps the @racket[map] function, allowing you to specify just the body of a lambda.

@irash{
;; =map= is in the demo file still
(require rash/demo/setup)
;; These two are the same.
|> list 1 2 3 |> map (λ (x) + 2 x)
|> list 1 2 3 =map= + 2
}

Pipeline operators are macros, and therefore can play any of the tricks that macros generally can in Racket.  The | operator can auto-quote symbols, turn asterisks into glob expansion code, etc.  The |> operator can detect whether the @racket[current-pipeline-argument] is used and insert it automatically.

If you put parentheses in the middle of a pipeline, you escape to normal Racket code.

@irash{
;; This will either show hidden files or give a long listing
ls (if (even? (random 2)) '-l '-a)
}

Lines of code in Rash are command pipelines by default, but there are key words called @racket[line-macro]s that can change the behavior arbitrarily.
@margin-note{Line-macros can be used to make C-like control-flow forms like for, try/catch, etc, to make one-off non-pipeline forms like @racket[cd], or even to make entirely new and different line-oriented languages.}

@irash{
;; in-dir is in the demo file still
(require rash/demo/setup)
in-dir $HOME/project {
  make clean
}
}

For instance, @racket[in-dir] executes code with @racket[current-directory] parameterized based on its first argument.  Note that logical rash lines don't necessarily line-up with physical lines.  Newlines can be escaped with a backslash, commented out with multiline comments, and if they are inside parentheses or braces they are handled by the recursive read.

@irash{
echo This is \
     all #|
     |# one (string-append
             "logical"
             "line")
}

Braces trigger a recursive line-mode read.  They are available in line-mode as well as in the embedded s-expression mode.  So they can be used to create blocks in line-mode as with the above @racket[in-dir] example, or be used to escape from the s-expression world to line-mode.

Note that subprocess pipelines are connected to stdout and stdin in the REPL and at the top level of @tt{#lang rash}.  The most common thing you want when embedding some Rash code is for subprocess output to be converted to a string.  Using @code{#{}} switches to line-mode with defaults changed so that subprocess output is converted to a string and passed through @racket[string-trim].

@irash{
;; #%hash-braces is provided by the demo library right now...
(require rash/demo/setup)
;; I do this a lot when I don't remember what a script does
cat #{which my-script.rkt}
}

TODO - how to more generally parameterize such settings.

Every line in Rash is actually a line-macro.  If a line does not start with a line-macro name explicitly, @racket[#%linea-default-line-macro] is inserted.  By default this is @racket[run-pipeline] in Rash.

TODO - actually the default is run-pipeline/logic, which I haven't documented yet, which adds && and ||.

You can also write normal parenthesized Racket code.  If the first (non-whitespace) character on a line is an open parenthesis, the line is read as normal Racket code and no line-macro is inserted.

@irash{
(define flag '-l)
ls $flag
}

Note that practically all Racket code starts with an open-paren, so Rash is almost a superset of normal Racket.  The only thing lost is top-level non-parenthesized code, which is really only useful to see the value of a variable.  Most programs in @tt{#lang racket/base} could be switched to @tt{#lang rash} and still function identically, and I never launch the Racket repl anymore because rash-repl is both a shell and a full Racket repl.

@irash{
(define x 1234)
;; Now let's see the value of x.
;; We can't just write `x`, but we can do any of these:
(values x)
|> values x
echo $x
(require rash/demo/setup)
val x
}

Avoiding line-macros by starting with a paren causes an annoying inconsistency -- you can't have a line-macro auto-inserted if the first argument to the line macro is a parenthesized form.

@irash{
;; We want to choose a compiler at runtime.
run-pipeline (if use-clang? 'clang 'gcc) -o prog prog.c
;; If we leave off the line-macro name, it will not be inserted
;; because the line starts with a parenthesis.
;; This will probably cause an error!
(if use-clang? 'clang 'gcc) -o prog prog.c
}

This problem can be fixed by prepending the line-macro name or by using [square] brackets instead of parentheses.  The issue doesn't come up much in practice, and it's a small sacrifice for the convenience of having both normal Racket s-expressions and Rash lines.

Rash is primarily a combination of two libraries --
@secref["linea" #:doc '(lib "linea/scribblings/linea.scrbl")],
which will explain the details of the line-oriented concrete syntax, and the
@secref["pipeline-macro" #:doc '(lib "shell/scribblings/shell-pipeline.scrbl")],
which will explain the details of the @racket[run-pipeline] macro and pipeline operators.
You should read their documentation as well if you want a more thorough understanding or Rash.

What else belongs in a quick overview?  Pipelines with failure codes don't fail silently -- they raise exceptions.  More fine-grained behavior can be configured per-pipeline, or using aliases (eg. whether other exit codes besides 0 are successful, whether to check for success in subprocesses in the middle of a pipeline, etc).  There are probably more things I should say.  But probably the best way forward from here is to read the @racket[run-pipeline] macro documentation.

You can define aliases with @racket[define-pipeline-alias] or @racket[define-simple-pipeline-alias].  Aliases are currently supported only by @racket[=unix-pipe=], though I may change that.  Aliases basically bypass the pipe itself -- basically so you can have @racket[=unix-pipe=] be the default operator but have a set of key-words that bypass it for a different operator without having to write the operator when it's in starting position.  And to be able to define aliases that are a little more familiar to people.

You can access environment variables with @racket[getenv] and @racket[putenv], or by accessing the @racket[current-environment-variables] parameter.  Individual pipelines should have some sugar to set environment variables more conveniently, but I haven't added that yet.  Also, the dollar escapes done by @racket[=unix-pipe=] access environment variables instead of normal lexical variables if you use a variable name in ALL CAPS.

Also, for those who just want to pipeline subprocesses in a Racket program using a lispy syntax, you probably want the shell/pipeline library, a basic component of Rash that can be used on its own:
@secref["pipeline" #:doc '(lib "shell/scribblings/shell-pipeline.scrbl")]

While you can use Rash as a #lang, you can also just use the bindings it exports via @racket[(require rash)].  Note that requiring the rash module will not affect the reader, so the line-oriented syntax will not be available unless you take steps to use it too (IE use the Linea reader, or use the @racket[rash] macro).


@section{Media}
I made a quick demo recording of an interactive repl
@hyperlink["https://asciinema.org/a/sHiBRIlSM9wHDetDhsVjrCaZi"]{here}.
It's a little out of date.  I should make a new and better one.

Also I gave a talk at RacketCon 2017 about it, which can be viewed
@hyperlink["https://www.youtube.com/watch?v=yXcwK3XNU3Y&index=13&list=PLXr4KViVC0qIgkwFFzM-0we_aoOfAl16Y"]{here}.
There have been various changes since the talk was given, but the core ideas are the same.  The biggest change since then is that embedding the line-syntax is encouraged with braces in the Linea syntax rather than string embedding.



@section{Rash Reference}

Note that all the pipeline things (@racket[run-pipeline],
@racket[=unix-pipe=], @racket[=object-pipe=],
@racket[define-pipeline-operator], etc) are documented in the
@secref["pipeline-macro" #:doc '(lib "shell/scribblings/shell-pipeline.scrbl")]
module.

All the things about reading and line-macros (@racket[define-line-macro], @racket[#%linea-line], etc) are documented in the
@secref["linea" #:doc '(lib "linea/scribblings/linea.scrbl")]
module.

TODO: document forms for configuring Rash besides the rash macro, document forms for creating customized versions of #lang rash (including reader modifications, default line-macro and pipeline operator, bindings available...), etc

@defform[(with-rash-config options ... body)]{

Configures the defaults for various options, and runs the body.

Options:

@racket[#:out] sets the default output port or transformer for unix pipelines (as run by @racket[run-pipeline]).  The default runs @racket[port->string] on the output.

@racket[#:in] sets the default input port for unix pipelines (as run by @racket[run-pipeline]).  The default is an empty port.

@racket[#:err] sets the default error port for unix pipelines (as run by @racket[run-pipeline]).  The default is to turn the errors into a string that is put into the exception generated by an error in the pipeline.

@racket[#:starter] sets the default starting pipeline operator for @racket[run-pipeline] when one is not explicitly given in the pipeline.  The default is @racket[=unix-pipe=].

@racket[#:line-macro] sets the default line-macro for lines that don't explicitly have one.  The default is the @racket[run-pipeline] line-macro.

Note that in, out, and err are evaluated once for each pipeline run in the body.
}

@defform[(splicing-with-rash-config options ... body)]{
The same as @racket[with-rash-config], but splicing a la @racket[splicing-let-syntax].
}

@defform[(rash options ... codestring)]{

Read @racket[codestring] as rash code.  Note that this happens during macro expansion, not at runtime.  This is useful to switch to Rash code in a module that uses a different reader.

Options:

The options are the same as @racket[with-rash-config].

TODO - options for changing the reader, etc.

Note that the input/output/error-output have different defaults for the rash macro than for the #lang or repl.

}

@defform[(make-rash-transformer options ...)]{
Semi-deprecated.

This takes all the same options as @racket[rash], but doesn't take a code string.  It produces a transformer like @racket[rash], but with different default values for the available options.

@(racketblock
(define-syntax my-rash (make-rash-transformer #:starter =basic-object-pipe=)))
}

@;@defform[(make-rash-module-begin-transformer options ...)]{
@;This takes all the same options as @racket[rash], but doesn't take a code string.  It produces a transformer like #%module-begin in #lang rash, but with different defaults and reader options.
@;
@;Use it to make a #lang that is like #lang rash but customized to your liking.
@;
@;@(racketblock
@;(define-syntax my-rash-module-begin
@;  (make-rash-module-begin-transformer #:starter #'=basic-object-pipe=)))
@;}

@;TODO - finish make-rash-reader-submodule and document it -- it should be like @racket[make-rash-transformer] only in should essentially create a #lang.
Note that the default #lang rash has its input/output/error-output as stdin/stdout/stderr, which is different than the rash macro.




@defform[#:kind "line-macro" (cd directory)]{
Change directory to given directory.  The directory is quoted, so just put a literal path or a string.

If no argument is given, it changes to the user's home directory.

Eventually this will be replaced by a better version, but it should be backwards compatible.
}

@defform[#:kind "line-macro" (run-pipeline arg ...)]{
Same as @racket[shell/pipeline-macro/run-pipeline], except wrapped as a line-macro.
}

@defparam[current-rash-top-level-print-formatter formatter (-> any/c string?)]{
Determines how expressions at the top of #lang rash modules (IE forms that aren't definitions) and expressions in the Rash REPL are printed.  Note that it doesn't actually do the printing -- it returns a string, which is then printed by the implicit printing wraps at the top of a module or (probably) by the @racket[current-prompt-function].

The default takes the result out of terminated pipelines to print rather than the pipeline object itself.  I plan to change the default.  But the idea of having this parameter is that you can set up your repl to print things in a more useful way, and then have it print the same way in a #lang rash script.
}

@section{Interactive Use}

You can run the repl by running @code{racket -l rash/repl}.  An executable named @code{rash-repl} is installed in Racket's bin directory, so if you have it on your path you can run @code{rash-repl} instead.

Various details of the repl will change over time.

Note that in the repl the default input/output/error-output are to the stdin/out/err connected to the terminal unless you change them.  This is different than the rash macro, and allows you to do things like run curses programs that have access to terminal ports.

The repl can be customized with rc files.
First, if $HOME/.config/rash/rashrc.rkt exists, it is required at the top level of the REPL.  Then, if $HOME/.config/rash/rashrc (note the lack of .rkt) exists, it is evaluated at the top level more or less as if typed in (much like rc files for bash and friends).  Note that @tt{rashrc.rkt} files are modules, can be in any #lang, and get all the normal and good compilation guarantees that Racket modules enjoy.  @tt{rashrc} is NOT a module, and gets none of them.  @tt{rashrc} is mainly there to let you muck up the namespace that you use interactively.  Prefer @tt{rashrc.rkt}.

Note that “the top-level is hopeless”.  This applies to the Rash REPL as well as @tt{rashrc} files.  But the hopelessness is mostly to do with defining macros, particularly complicated macros such as mutually recursive or macro-defining macros.  So the hopelessness doesn't affect the types of things most people are likely to do in a shell.  But if you don't remember that, you might put “hopeless” things in a @tt{rashrc} file.  Don't.  Put it in a module like @tt{rashrc.rkt} (or any other module or library you make).  (For more hopelessness, see @hyperlink["https://gist.github.com/samth/3083053"]{this}.)

A few nice things (like stderr highlighting) are in a demo-rc file you can require.  To do so, add this to $HOME/.config/rash/rashrc:

@verbatim|{
(require rash/demo/demo-rc)
}|

(Rash actually follows the XDG basedir standard -- you can have rashrc.rkt or rashrc files in any directory of $XDG_CONFIG_HOME or $XDG_CONFIG_DIRS, and the rash repl will load all of them)

The repl uses the readline module for line-editing and completion.  The readline module by default uses libedit (or something like that) instead of the actual libreadline for licensing reasons.  Libedit doesn't seem to handle unicode properly.  Installing the readline-gpl package fixes that (@tt{raco pkg install readline-gpl}).

All the following repl functions are not stable.

@defproc[(result-n [n integer?]) any/c]{
Only available in the repl.  Return the result of the @racket[n]th interactive command.
}

@defform[(set-default-pipeline-starter! new-starter)]{
Only available in the repl.
A line-macro that mutates the default pipeline starter used in the repl.
It's not really hygienic, so if you defined macros that used @racket[run-pipeline] without an explicit starter, this will change the result of new calls to that macro.
Basically a hack to be able to set it since I haven't figured out a better way to do it yet, aside from maybe having people make their own repl modules that set some defaults, and I'm not sure I like that plan.
Expect this to change eventually.
}

@defform[(set-default-line-macro! new-line-macro)]{
Only available in the repl.
A line-macro that mutates the default line macro used in the repl.
It's not really hygienic.
Basically a hack to be able to set it since I haven't figured out a better way to do it yet, aside from maybe having people make their own repl modules that set some defaults, and I'm not sure I like that plan.
Expect this to change eventually.
}

@defparam[current-prompt-function prompt procedure?]{
You can set this parameter to change the prompt.  The prompt is responsible for printing the result returned by whatever was last run as well as showing any information you want to see.  Right now I would just stick with the default, but I plan on making a nice library of useful functions to put in a prompt (eg. functions for displaying git information, path information with length pruning, ...), and have a way of easily connecting some prompt pieces to make something good (including a way to customize how results are displayed -- I want to, for example, have types of objects that can be recognized to print tables nicely, etc).

The given function's arity is tested to see if it receives various keywords, so that the protocol can be extended and the user only has to specify the keywords that are needed for a given prompt.

Keywords optionally given:

@racket[#:last-return-value] - fairly self explanatory.  If multiple values were returned, they will be given as a list.  This will be @racket[(void)] for the prompt before the first command.  The default prompt function formats the return value with @racket[current-rash-top-level-print-formatter] before printing it.

@racket[#:last-return-index] - This increments once for every command run in the repl.  It will be 0 for the prompt before the first command.  This is the index that can be used for @racket[result-n] and @racket[result-n].  The default prompt function prints the number of the result before printing the result itself.
}



@section{Prompt helpers}

There are currently a few functions that can help you design a custom prompt.  Currently, they only support things like changing foreground/background color and underlined text, but they will be expanded in the future to include more useful ways of getting information for your prompt.

You can use them with @tt{(require rash/prompt-helpers/string-style)}
@declare-exporting[rash/prompt-helpers/string-style]

@(define prompt-helper-eval (make-base-eval))
@defproc[(create-styled-string [to-style string? ""]
                               [#:fg foreground color-value?]
                               [#:bg background color-value?]
                               [#:bold? bold? boolean? #f]
                               [#:italic? italic? boolean? #f]
                               [#:underlined? underlined? boolean? #f]
                               [#:reset-before? reset-before? boolean? #t]
                               [#:reset-after? reset-after? boolean? #t]
                               [#:custom-commands custom-commands string? ""]
                               [#:create-function? create-function? boolean? #f])
         (or/c string? (-> string? string?))]{
 Produces a string with the specified styles.

 The values given for @racket[foreground] and @racket[background] are treated the same.  If a string is given, it must either be the name of a 4 bit color, eg. @racket["red"], or start with the charachter "#" and represent a hexidecimal color code, eg @racket["#f2e455"].  If a number is given, it is treated as a color code for a 8bit/256color color.  If a list is given, it is treated as an RGB value for a color, eg. @racket['(0 0 0)] means black.  An object with @racket[red], @racket[green], and @racket[blue] methods (like @racket[color%]) can also be given, and are treated like RGB values.

 The values @racket[bold?], @racket[italic?], and @racket[underlined?] do what you'd expect them to.

 If @racket[reset-before?] is @racket[#t], then the ANSI escape sequence "\033[0m" will be added to the front of the string.  When @racket[display]ed, it has the effect of clearing all styles set by ANSI escape sequences before itself.  Similarily, if @racket[reset-after?] is @racket[#t], the sequence "\033[0m" is appended to the end of the string.

 The string @racket[custom-commands] is placed right before @racket[to-style], so any styles in the form of ANSI escape sequences can be added overridden if desired.

 If @racket[create-function?] is @racket[#t], then a function is returned instead of a string.  This function takes 1 argument and places that argument where @racket[to-style] would have went, and returns the resulting string.

 @margin-note{I cant display the actual colors here, but you can copy the resulting strings into a terminal and print them with @exec{echo "string"} or display them using @racket[display] in a terminal window.}
 
 @interaction-eval[#:eval prompt-helper-eval
                   (require rash/prompt-helpers/string-style)]
 @examples[
 #:eval prompt-helper-eval
 (create-styled-string "example"
                       #:bg "red"
                       #:fg '(255 255 255)
                       #:underlined? #t)
 
 (create-styled-string "example"
                       #:bg "red"
                       #:fg '(255 255 255)
                       #:underlined? #t
                       #:reset-before? #f)
 (define style-function (create-styled-string #:bg "red"
                                              #:create-function? #t))
 
 (style-function "I'm red!")
 ]}


@defproc[(color-value? [v any/c])
         boolean?]{Thoroughly determines whether @racket[v] is a valid color argument.  See @racket[create-styled-string] for valid color arguments.}


@defproc[(create-styled-struct [to-style (or/c string? struct?)] ...
                               [#:fg foreground (or/c color-value? default) default]
                               [#:bg background (or/c color-value? default) default]
                               [#:bold? bold? (or/c boolean? default) default]
                               [#:italic? italic? (or/c boolean? default) default]
                               [#:underlined? underlined? (or/c boolean? default) default]
                               [#:reset-before? reset-before? boolean? #f]
                               [#:custom-commands custom-commands string? ""]
                               [#:reset-customs? reset-customs? #f])
         styled-struct?]{
 Mostly the same as @racket[create-styled-string], except a structure with a list of strings/sub-structs and a style represented by a hash is produced.  This struct can be given to @racket[styled-struct->string] to turn it into a string.  An uninterned symbol is used as the @racket[default] value for some of the optional arguments.  The function treats the @racket[default] argument to mean "use the style the outer struct provides".
                    
 @examples[
 #:eval prompt-helper-eval
 (create-styled-struct "I'm green. "
                       (create-styled-struct "Im green with red text."
                                             #:fg "red")
                       #:bg "green")]
}


@defproc[(styled-struct->string [ss styled-struct?]
                                [outer-style-hash hash? #hash((foreground . #f)
                                                              (background . #f)
                                                              (bold? . #f)
                                                              (italic? . #f)
                                                              (underlined? . #f)
                                                              (reset-before? . #t)
                                                              (custom-commands . "")
                                                              (reset-customs? . #t))])
         string?]{
 Takes a structure produced by @racket[create-styled-struct], and recursively produces a string from it.  If it finds another struct within @racket[ss], it will convert it to a string in it's position in @racket[ss], and will use the sub-struct's style properties to override @racket[ss]'s properties if specified.

 If @racket[reset-before?] is @racket[#t] for a struct (within its style hash), that struct will ignore the styles provided by an outer struct.  If @racket[reset-customs?] is @racket[#t] for a struct, that struct will ignore custom commands given by its outer struct and only use it's own.

 @examples[
 #:eval prompt-helper-eval
 #:label "Examples (Sorry for the long strings):"
 
 (define example1
  (styled-struct->string
   (create-styled-struct
    "I'm green and hilighted blue."
    (create-styled-struct
     "Im still green but higighted yellow and underlined."
     #:bg "yellow"
     #:underlined? #t)
    " I'm green and hilighted blue again (and not underlined)"
    #:fg "green"
    #:bg "blue")))

 (code:line (regexp-split #px"\\." example1) (code:comment "so it fits on the screen"))
 
 (define example2
   (styled-struct->string
    (create-styled-struct
     #:underlined? #t
     #:bg "blue"
     "Underlined."
     (create-styled-struct
      #:underlined? #f
      "Not underlined.")
     "Underlined."
     (create-styled-struct
      #:reset-before? #t
      "\n"))))
 (regexp-split #px"\\." example2)]
}



@section{Demo stuff reference}

Nothing in the demo directory is remotely stable!  It can all change or go away at any moment.

I've written various pipeline operators and line macros that I use, but I haven't decided what should be in the default language yet.  So for now they are sitting in a demo directory.  But I need some examples.  So here I'm documenting a bit.

Use it with @tt{(require rash/demo/setup)}.
@(declare-exporting rash/demo/setup)


@defform[#:kind "pipeline-operator" (=map= arg ...)]{
Sugar to flatten mapping.

Eg.

@irash{
|> list 1 2 3 4 =map= + _ 1
}
is equivalent to
@irash{
(map (λ (x) (+ x 1)) (list 1 2 3 4))
}

The @racket[_] argument is appended to @racket[=map=]'s argument list if it is not written explicitly.
}

@defform[#:kind "pipeline-operator" (=filter= arg ...)]{
Sugar to flatten filtering.

Eg.

@irash{
|> list 1 2 3 4 =filter= even?
}
is equivalent to
@irash{
(filter (λ (x) (even? x)) (list 1 2 3 4))
}

The @racket[_] argument is appended to @racket[=filter=]'s argument list if it is not written explicitly.
}


@defform[#:kind "line-macro" (in-dir directory body)]{
Dollar and glob expands the @racket[directory], then executes the @racket[body] with @racket[current-directory] parameterized to the result of expanding @racket[directory].  If glob expansion returns multiple results, the body is executed once for each of them.

Eg.

@irash{
in-dir $HOME/projects/* {
  make clean
  make
}
}
}

@defform[#:kind "line-macro" (val expression)]{
Simply returns the @racket[expression].  This is just to work around not having access to top-level unparenthesized variables.
}



@section{Code and License}

The code is available
@hyperlink["https://github.com/willghatch/racket-rash"]{on github}.

This library is licensed under the terms of the LGPL version 3, or (at
your option) any later version published by the Free Software
Foundation (IE LGPL3+).
