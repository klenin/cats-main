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
<a href='<TMPL_VAR href_page>'><TMPL_VAR page_number></a> 
</TMPL_IF>
</TMPL_LOOP>
<TMPL_IF href_next_pages><a href='<TMPL_VAR href_next_pages>'>&gt;&gt;</a></TMPL_IF>
</td>
<td width=20% align=center>
выбирать
<select name="history">
<option value='1hour'<TMPL_IF history_1hour> selected</TMPL_IF>>за последний час
<option value='24hours'<TMPL_IF history_24hours> selected</TMPL_IF>>за сутки
<option value='all'<TMPL_IF history_all> selected</TMPL_IF>>все
</select>
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