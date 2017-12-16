# CATS Coding Style

This document describes coding style conventions used by CATS project.
Code for this project is located in `cats-main`, `cats-judge` and `cats-problem` repositories.

## Required conventions
Required conventions are designated by words MUST and MUST NOT.
Existing code (mostly) conforms with required conventions.
Non-conforming contributions will probably be rejected.
Patches fixing violations in existing code will probably be accepted.

## Recommended conventions
Recommended conventions are designated by words SHOULD and SHOULD NOT.
Existing code partially conforms with recommended conventions. However, there are significant exceptions due to either historical or practical reasons.
Non-conforming contributions may be accepted if there is a good reason for violation.
Patches fixing violations of recommended conventions in existing code without any other changes will probably be rejected.

## Absent conventions
Absent conventions are designated by word MAY.
Those choices are explicitly not standardized and allowed be different in each instance.

## Deprecated code
Some historical code, mostly located in `unused` directory, does not conform to any conventions and is not expected to ever change.

## Whitespace
* Perl code MUST be indented by 4 (four) spaces.
* Template and Javascript code SHOULD be indented by 2 (two) spaces.
* Code MUST NOT contain trailing spaces. In particular, spaces to the right of operators demanded by conventions below MUST NOT be present if the line is split after the operator.
* Code MUST NOT contain tab characters.
* Operators, including fat comma (`=>`) and conditional (`?:`) MUST be surrounded by a single space from each side.
* Comma MUST be have a single space on the right and MUST NOT have a space on the left.
* Multiple assignments or array/hash constructors MAY be presented in tabular form by aligning items vertically with spaces. Otherwise, whenever space is used between tokens, it MUST be a single space.
* Functions and `use` statement categories MUST be separated by a single empty line.
* Single empty lines MAY be used to separate logical blocks of code.
* Code MUST not have two or more consecutive empty lines.
* Parentheses MUST NOT have spaces inside.
* Parentheses MUST have spaces outside except between subroutine name and parameter list, where space MUST NOT be present.
* Square brackets MUST NOT have spaces inside when they designate array access and MUST have spaces inside otherwise (`$v[1]` but `[ 1, 2, 3 ]`).
* Curly brackets MUST NOT have spaces inside when they designate defererence or hash access and MUST have spaces inside otherwise (`$h{$k}` and `@{f()}` but `{ x => 1 }`).
* Code lines MUST be shorter than 120 characters.
* Code lines SHOULD be shorter than 100 characters.
* When a statement is split into several lines, split position SHOULD be after the operator of the lowest possible priority. Exception: if a line is split at the position of low-priority logical operator (`and`, `or`), such operator MUST go on the new line.
* Semicolon MUST NOT have space on the left and SHOULD be followed by either a comment or end of line.

## Statements and blocks
* There SHOULD be no more than one statement per line.
* For compound statements and subroutines, opening braces of body code blocks MUST be at the end of the line, not on a separate line.
* When splitting long condition of the prefix compund statement into several lines, closing parentheses together with opening brace SHOULD be split into a separate line with the same identation as the compound statement.
* Prefix and suffix compound statements as well as low-priority logical operators MAY be used interchangeably.
* Suffix compound statements MUST NOT have parentheses around the condition.
* Low-priority logical operators MUST NOT be used inside of statements (`if ($x and $y)` is wrong).
* High-priority logical operators MUST NOT be used between statements (`$x || return` is wrong).
* Embedded SQL MUST start from a new line, after opening quote. Exception: very short SQL parts during request construction.
* Parameters passed to SQL statement MUST start from the new line.
* Lists spanning more than one line SHOULD have a trailing comma.
* Redundant parentheses SHOULD be omitted.
* `for` keyword MUST be used instead of `foreach`.
* Parameter assignment MUST be the first line of subroutine and SHOULD be of the form `my ($p1, $p2, ...) = @_;`.
* Subroutines MUST NOT use prototypes (exception: `()` for constants).
* Single-statement subroutines SHOULD omit trailing semicolon.
* Subroutines SHOULD omit the `return` keyword in the final statement.

## Comments
* Comments MUST be worded as full English sentences, with capitalization and periods.
* Comment MUST have a single space between `#` character and text.
* Comments MUST be either on a separate line immediately preceding commented code or at the end of the commented line. First option SHOULD be preferred.
* Commented-out code SHOULD NOT be committed.
* Subroutines accepting named parameters SHOULD be preceded by a comment with a list of parameter names.

## Quoting
* Strings without interpolation MUST use single quotes.
* Regexps SHOULD use slash.
* With alternative quoting, tilde character MUST be used for both strings and regexps (`q~`, `qq~`, `m~`, `s~`).
* Alternative quoting with tilde MUST be used for all embedded SQL.
* Identifiers used as hash keys MUST NOT be quoted (except where required by language).

## Identifiers and packages
* Package/class identifiers MUST use `CamelCase` and reside in `CATS::` namespace (exception: `cats` package for global constants defined in `CATS::Constants`).
* All other identifiers MUST use `snake_case`.
* Object instance variable MUST be named `$self`.
* Packages MUST NOT export anything by default (exception: `CATS::DB`).
* `use` statements MUST be sorted alphabetically inside of each category. Categories MUST be listed in the following order:
    * directives
    * `Exporter`
    * standard and external packages
    * CATS packages.
* Import lists MUST use `qw()` and MUST be sorted alphabetically.
* New code SHOULD NOT introduce new global variables.
* Leading underscore MAY be used to indicate package-local subroutines.
* Packages MUST be less than 1000 lines long.
* File MAY contain several packages.
* Package names SHOULD correspond to file names according to standard Perl convention.
* Inner scope identifiers MUST NOT shadow outer scope ones.

## Strictness and warnings
* All modules MUST start from `use strict` and `use warnings` statements.
* `no strict` / `no warnings` statement MUST be enclosed in the smallest possible block.
* Code MUST NOT generate any warnings.

## Security
* User-supplied values MUST be passed to SQL via parameters only.
* User-supplied strings MUST be quoted with either `html` or `$Javascript` filter in templates.
* HTTP parameters SHOULD be verified using `CATS::Router`.

## Templates
* CATS-specific URLs MUST be generated by Perl code (using `url_f`/`url_function`).
* User-visible text in templates MUST be internationalized (see `lang` directory).
* `PROCESS` directive SHOULD be preferred to `INCLUDE` unless variable localization is actually required.
* `PROCESS` and `INCLUDE` directive MUST NOT use quotes around argument except when interpolation is required.
* Templates SHOULD try to avoid extra whitespace in HTML by using `[%- -%]` and `[%~ ~%]` constructs.
* Templates MUST use loop variable in `FOREACH` loops.

## HTML
* Html MUST be valid HTML5 (except for user-supplied problem texts).
* Attributes MUST be quoted, even if HTML allows otherwise.
* Void elements MUST be closed XML-style (`<br/>`).
* Non-void elements MUST have explicit closing tag, even if empty (`<td></td>`).
* Forms MUST be submitted with `button`, NOT `input`.
* Elements SHOULD be styled with CSS, embedded `style` tags MAY be used for local styles (using `extra_head` block).
* Checkboxes and submit buttons MUST have `value="1"`.

## SQL
* SQL keywords and table aliases MUST use `UPPER CASE`.
* Table and field names MUST use `snake_case`.
* Comments SHOULD use `/* ... */` style.
* Joins MUST use `JOIN` keyword, not comma.
* `CHECK` constraints SHOULD be named.
* Each foreign key MUST contain `ON DELETE` clause.

## Compatibility
* Code from `cats-main` and `cats-problem` repositories MUST be compatible with Perl v5.10.
* Code from `cats-judge` repository MUST be compatible with Perl v5.14.
* Contributions SHOULD NOT add dependency on new non-standard modules without prior discussion.

## Architecture
* Templates MUST NOT change any state of the model.
* Controllers (`xxx_frame`) MUST be called only by `Router`.
* Controllers MUST be defined only in `CATS::UI::`namespace. `CATS::UI` modules MUST be used only by `Router`.
* SQL structure changes MUST include migration in the same commit.

## Git commits
* Each commit MUST result in working code (and pass tests, where applicable). Temporary breakage in PRs is not allowed, use feature checks when needed.
* Commit message SHOULD start from affected subsystem name, followed by a colon, a space and a subject text.
* Subsystem name MAY be a module name, page name, directory name or several names separated by comma plus space.
* Commit message subject SHOULD be a single English statement.
* Single-statement commit message MUST NOT end with period.
* Commit message MUST NOT contain double quotes. Single quotes MAY be used around indentifiers in the message.
* Commit message MUST NOT be longer than 80 characters.
* Commit message referencing a GitHub issue SHOULD do it by adding `See #issue` at the end of the subject. Multiple issues MAY be referenced from message body.
* Commit message auto-closing a GitHub issue MUST do it by adding `Fixes #issue` at the end of the subject.
