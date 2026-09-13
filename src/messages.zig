pub const PRIMARY_EXPR =
    \\What are primary expressions:
    \\
    \\    :<tag>         - checks if task has a tag
    \\    [ <expr> ]     - same as previous but for Bash users
    \\    not <primary>  - negation of a primary expression
    \\    any            - expression that always returns true
    \\    tagged         - checks if a task is tagged
    \\    priority       - priority of a task as an integer
    \\    <number>       - signed integer
    \\    <huid>         - valid id of a task
    \\
;

pub const INFIX_OPERATORS =
    \\ Supported infix operators:
    \\
    \\    and  or                  - logical operators
    \\    lt  le  gt  ge  eq  ne   - comparison operators
    \\
;
