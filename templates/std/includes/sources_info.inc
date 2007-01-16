<table class="internal_borders" cellpadding="3">
<tr><th>Команда</th><TMPL_LOOP sources_info><td><b><TMPL_VAR team_name></b></td></TMPL_LOOP></td></tr>
<tr><th>ID</th><TMPL_LOOP sources_info><td><TMPL_VAR req_id></td></TMPL_LOOP></td></tr>
<tr><th>Время</th><TMPL_LOOP sources_info><td><TMPL_VAR submit_time></td></TMPL_LOOP></td></tr>
<tr><th>Обработка</th><TMPL_LOOP sources_info><td><TMPL_VAR test_time_short> ... <TMPL_VAR result_time_short></td></TMPL_LOOP></td></tr>
<tr><th>Язык</th><TMPL_LOOP sources_info><td><TMPL_VAR de_name></td></TMPL_LOOP></td></tr>
<tr><th>Файл</th><TMPL_LOOP sources_info><td><TMPL_VAR file_name></td></TMPL_LOOP></td></tr>
<tr><th>Турнир</th><TMPL_LOOP sources_info><td><TMPL_VAR contest_name></td></TMPL_LOOP></td></tr>
<tr><th>Задача</th><TMPL_LOOP sources_info><td>
  <TMPL_IF href_contest_problems><a href="<TMPL_VAR href_contest_problems>"><TMPL_VAR problem_name></a>
  <TMPL_ELSE><TMPL_VAR problem_name></TMPL_IF>
</td></TMPL_LOOP></td></tr>
<TMPL_IF is_jury>
<tr><th>Судья</th><TMPL_LOOP sources_info><td><TMPL_VAR judge_name></td></TMPL_LOOP></td></tr>
</TMPL_IF>
<tr><th>Состояние</th>
<TMPL_LOOP sources_info><td>
<TMPL_IF not_processed><font color="#008000">Not processed</TMPL_IF>
<TMPL_IF install_processing><font color="#a0a000">Installing problem</TMPL_IF>
<TMPL_IF unhandled_error>Unhandled error</TMPL_IF>
<TMPL_IF testing><font color="#a0a000">Now testing</TMPL_IF>
<TMPL_IF accepted>Solution accepted</TMPL_IF>
<TMPL_IF wrong_answer>Wrong answer on test <TMPL_VAR failed_test></TMPL_IF>
<TMPL_IF presentation_error>Presentation error on test <TMPL_VAR failed_test></TMPL_IF>
<TMPL_IF time_limit_exceeded>Time limit exceeded on test <TMPL_VAR failed_test></TMPL_IF>
<TMPL_IF memory_limit_exceeded>Memory limit exceeded on test <TMPL_VAR failed_test></TMPL_IF>
<TMPL_IF runtime_error>Runtime error on test <TMPL_VAR failed_test></TMPL_IF>
<TMPL_IF compilation_error>Compilation error</TMPL_IF>
<TMPL_IF security_violation>Security violation</TMPL_IF>
</td></TMPL_LOOP>
</tr>
<tr><th>Ссылки</th>
<TMPL_LOOP sources_info><td>
<TMPL_IF href_view_source><a href="<TMPL_VAR href_view_source>">код</a><TMPL_ELSE>код</TMPL_IF> |
<TMPL_IF href_download_source><a href="<TMPL_VAR href_download_source>">скачать</a></TMPL_IF> |
<TMPL_IF href_run_details><a href="<TMPL_VAR href_run_details>">результаты</a><TMPL_ELSE>результаты</TMPL_IF>
<TMPL_IF is_jury> |
<TMPL_IF href_run_log><a href="<TMPL_VAR href_run_log>">лог</a><TMPL_ELSE>лог</TMPL_IF>
</TMPL_IF>
</td></TMPL_LOOP>
</tr>
</table>

<form action="<TMPL_VAR href_current_link>" method="post">
  <select name="src_enc">
  <TMPL_LOOP source_encodings>
  <option value="<TMPL_VAR enc>"<TMPL_IF selected>selected="selected"</TMPL_IF>><TMPL_VAR enc></option>
  </TMPL_LOOP>
  </select>
  <input type="submit" value="кодировка" />
</form>
