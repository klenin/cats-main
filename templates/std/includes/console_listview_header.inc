<table width=100%>
<tr>
<td align=left width=20% nowrap>
<input type=submit value="Найти" name=filter class=button>
<input type=text name="search" value="<TMPL_VAR search>" size="30" class=bordered>
</td>
<td align=center width=20% nowrap>
<TMPL_IF href_prev_pages><a href='<TMPL_VAR href_prev_pages>'>&lt;&lt;</a></TMPL_IF>

страницы:

<TMPL_LOOP pages>
<TMPL_IF current_page>
<TMPL_VAR page_number> 
<TMPL_ELSE>
<a href="<TMPL_VAR href_page>"><TMPL_VAR page_number></a> 
</TMPL_IF>
</TMPL_LOOP>
<TMPL_IF href_next_pages><a href="<TMPL_VAR href_next_pages>">&gt;&gt;</a></TMPL_IF>
</td>
<td width=20% align=center>
выбирать
<select name="history_interval_value">
<TMPL_LOOP history_interval_value>
    <option value="<TMPL_VAR value>"<TMPL_IF selected> selected</TMPL_IF>><TMPL_VAR text></option> 
</TMPL_LOOP>
</select>
<select name="history_interval_units">
<TMPL_LOOP history_interval_units>
    <option value="<TMPL_VAR value>"<TMPL_IF selected> selected</TMPL_IF>><TMPL_VAR text></option> 
</TMPL_LOOP>
</select>

<TMPL_IF user_filter><a href="<TMPL_VAR href_all_events>">все</a>
<TMPL_ELSE><a href="<TMPL_VAR href_my_events_only>">мои</a></TMPL_IF>
</td>
<td align=right width=20% nowrap>
<input type=submit value="Показывать" name=visible class=button>
<select name=display_rows>
<TMPL_LOOP display_rows>
    <option value="<TMPL_VAR count>" <TMPL_IF is_current> selected </TMPL_IF> ><TMPL_VAR text>
</TMPL_LOOP>
</select>
</td>
</tr>
</table>
