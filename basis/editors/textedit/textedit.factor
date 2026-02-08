USING: editors kernel make ;
IN: editors.textedit

SINGLETON: textedit

M: textedit editor-command
    drop
    [ "open" , "-a" , "TextEdit" , , ] { } make ;
