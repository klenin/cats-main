<table width=100%>
<tr>
<td align=left>
<input type=submit value="Найти" name=filter class=button>
<input type=text name="search" value="<TMPL_VAR search>" size="30" class="bordered">
</td>
<td align=center>
<TMPL_IF href_prev_pages><a href="<TMPL_VAR href_prev_pages>">&lt;&lt;</a></TMPL_IF>
страницы:
<TMPL_LOOP pages>
<TMPL_IF current_page><TMPL_VAR page_number>
<TMPL_ELSE><a href="<TMPL_VAR href_page>"><TMPL_VAR page_number></a> </TMPL_IF>
</TMPL_LOOP>
<TMPL_IF href_next_pages><a href="<TMPL_VAR href_next_pages>">&gt;&gt;</a></TMPL_IF>
</td>
<td align=center>
выбирать:
<TMPL_IF user_filter><a href="<TMPL_VAR href_all_events>">все</a>
<TMPL_ELSE><a href="<TMPL_VAR href_my_events_only>">мои</a></TMPL_IF>
<input type="checkbox" id="show_contests" name="show_contests" <TMPL_IF show_contests> checked="checked"</TMPL_IF>/>
<label for="show_contests" title="турниры">т</label>
<input type="checkbox" id="show_messages" name="show_messages" <TMPL_IF show_messages> checked="checked"</TMPL_IF>/>
<label for="show_messages" title="сообщения">с</label>
<input type="checkbox" id="show_results" name="show_results" <TMPL_IF show_results> checked="checked"</TMPL_IF>/>
<label for="show_results" title="результаты">р</label>
за <select name="i_value">
<TMPL_LOOP i_values>
    <option value="<TMPL_VAR value>"<TMPL_IF selected> selected</TMPL_IF>><TMPL_VAR text></option> 
</TMPL_LOOP>
</select>
<select name="i_unit">
<TMPL_LOOP i_units>
    <option value="<TMPL_VAR value>"<TMPL_IF selected> selected</TMPL_IF>><TMPL_VAR text></option> 
</TMPL_LOOP>
</select>
</td>
<td align=right width=20%>
<input type=submit value="Показывать" name=visible class=button>
<select name="rows">
<TMPL_LOOP display_rows>
    <option value="<TMPL_VAR count>" <TMPL_IF is_current> selected </TMPL_IF> ><TMPL_VAR text>
</TMPL_LOOP>
</select>
</td>
</tr>
</table>
