<table class="internal_borders" cellpadding="3">
<tr><th>ID</th><TMPL_LOOP sources_info><td><TMPL_VAR req_id></td></TMPL_LOOP></td></tr>
<tr><th>Время</th><TMPL_LOOP sources_info><td><TMPL_VAR submit_time></td></TMPL_LOOP></td></tr>
<tr><th>Язык</th><TMPL_LOOP sources_info><td><TMPL_VAR de_name></td></TMPL_LOOP></td></tr>
<tr><th>Файл</th><TMPL_LOOP sources_info><td><TMPL_VAR file_name></td></TMPL_LOOP></td></tr>
<tr><th>Команда</th><TMPL_LOOP sources_info><td><TMPL_VAR team_name></td></TMPL_LOOP></td></tr>
<tr><th>Турнир</th><TMPL_LOOP sources_info><td><TMPL_VAR contest_name></td></TMPL_LOOP></td></tr>
<tr><th>Задача</th><TMPL_LOOP sources_info><td><TMPL_VAR problem_name></td></TMPL_LOOP></td></tr>
</table>
