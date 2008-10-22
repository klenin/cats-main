<TMPL_LOOP col_defs>
<th <TMPL_IF width>width="<TMPL_VAR width></TMPL_IF>">
  <a href="<TMPL_VAR href_sort>" style="color:black"><TMPL_VAR caption
><TMPL_IF sort_up><img src="./images/std/sortup.gif" border="0" alt="up"></TMPL_IF
><TMPL_IF sort_down><img src="./images/std/sortdown.gif" border="0" alt="down"></TMPL_IF></a>
</th>
</TMPL_LOOP>