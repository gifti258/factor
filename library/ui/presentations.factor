! Copyright (C) 2005 Slava Pestov.
! See http://factor.sf.net/license.txt for BSD license.
IN: gadgets-presentations
USING: compiler gadgets gadgets-buttons gadgets-labels
gadgets-menus gadgets-panes generic hashtables inference
inspector io jedit kernel lists memory namespaces parser
prettyprint sequences styles vectors words ;

SYMBOL: commands

{ } clone commands global set-hash

: define-command ( class name quot -- )
    3vector commands get push ;

: applicable ( object -- seq )
    commands get [ first call ] subset-with ;

: command-quot ( presented quot -- quot )
    [
        [ swap literalize , % ] [ ] make ,
        [ pane get pane-call ] %
    ] [ ] make ;

: command-menu ( presented -- menu )
    dup applicable
    [ [ third command-quot ] keep second swons ] map-with
    <menu> ;

: init-commands ( gadget -- gadget )
    dup presented paint-prop [
        [
            \ drop ,
            literalize ,
            [ command-menu show-menu ] %
        ] [ ] make
        <roll-button>
    ] when* ;

: <styled-label> ( style text -- label )
    <label> swap dup [ alist>hash ] when over set-gadget-paint ;

: <presentation> ( style text -- presentation )
    gadget pick assoc dup
    [ 2nip ] [ drop <styled-label> init-commands ] ifte ;

: <object-presentation> ( object -- gadget )
    dup presented swons unit swap unparse-short <presentation> ;

: gadget. ( gadget -- )
    gadget swons unit
    "This stream does not support live gadgets"
    swap format terpri ;

[ drop t ] "Prettyprint" [ . ] define-command
[ drop t ] "Inspect" [ inspect ] define-command
[ drop t ] "Inspect variable" [ get inspect ] define-command
[ drop t ] "Inspect references" [ references inspect ] define-command
[ drop t ] "Push on data stack" [ ] define-command

[ word? ] "See word" [ see ] define-command
[ word? ] "Word usage" [ usage . ] define-command
[ word? ] "Open in jEdit" [ jedit ] define-command
[ word? ] "Reload original source" [ reload ] define-command
[ compound? ] "Annotate with watchpoint" [ watch ] define-command
[ compound? ] "Annotate with breakpoint" [ break ] define-command
[ compound? ] "Annotate with profiling" [ profile ] define-command
[ word? ] "Compile" [ recompile ] define-command
[ word? ] "Show stack effect" [ unit infer . ] define-command
[ word? ] "Show dataflow IR" [ word-def t dataflow. ] define-command
[ word? ] "Show linear IR" [ precompile ] define-command

[ [ gadget? ] is? ] "Display gadget" [ gadget. ] define-command
