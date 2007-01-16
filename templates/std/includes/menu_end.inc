</div>
<table width="100%" cellspacing="0" cellpadding="0">
<tr bgcolor="#7070ff" height="30" class="top">
  <td class="signed">
    текущий пользователь: 
    <TMPL_IF current_team_name><TMPL_VAR current_team_name ESCAPE=HTML>
    <TMPL_ELSE>анонимный
    </TMPL_IF>
  </td>
  <td align="right">
    <a href="./docs/" class="signed">документация</a> |
    <a href="<TMPL_VAR url_authors>" class="signed">&copy; 2002-2006 Авторы</a>&nbsp;
  </td>
</tr>
<tr bgcolor="#ffcc55" height="40">
  <td background="./images/std/bg2.gif" class="down">
    &nbsp;<font size="-3" color="#808080"><TMPL_VAR request_process_time></font>
  </td>
  <td align="right">
	<a href="http://imcs.dvgu.ru" class="signed2"> Институт математики и компьютерных наук&nbsp;<br> Дальневосточный государственный университет &nbsp;</a>
  </td>
</tr>
</table>
</body>
</html>