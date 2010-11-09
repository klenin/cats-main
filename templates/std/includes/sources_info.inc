<table class="internal_borders" cellpadding="3">
<tr><th>ID</th><TMPL_LOOP sources_info><td><TMPL_VAR req_id></td></TMPL_LOOP></tr>
<tr><th>Команда</th><TMPL_LOOP sources_info><td><a href="<TMPL_VAR href_stats>"><TMPL_VAR team_name></a>
<TMPL_IF is_jury>
  [<a href="http://geotool.flagfox.net/?ip=<TMPL_VAR last_ip_short>" alt="<TMPL_VAR last_ip>" title="<TMPL_VAR last_ip>"><TMPL_VAR last_ip_short></a>]
</TMPL_IF>
</td></TMPL_LOOP></tr>
<tr><th>Время</th><TMPL_LOOP sources_info
  ><td>
  <TMPL_IF href_prev_attempt> <a href="<TMPL_VAR href_prev_attempt>"><TMPL_VAR prev_attempt_time>&lt;&lt;</a></TMPL_IF>
  <TMPL_VAR submit_time>
  <TMPL_IF href_next_attempt> <a href="<TMPL_VAR href_next_attempt>"><TMPL_VAR next_attempt_time>&gt;&gt;</a></TMPL_IF>
</td></TMPL_LOOP></tr>
<tr><th>Обработка</th><TMPL_LOOP sources_info><td>
<TMPL_IF is_jury><TMPL_VAR judge_name>: </TMPL_IF>
<TMPL_VAR test_time_short> ... <TMPL_VAR result_time_short></td></TMPL_LOOP></tr>
<tr><th>Файл</th><TMPL_LOOP sources_info><td><TMPL_VAR file_name> (<TMPL_VAR de_name>)</td></TMPL_LOOP></tr>
<tr><th>Турнир</th><TMPL_LOOP sources_info><td>
  <TMPL_IF href_contest><a href="<TMPL_VAR href_contest>"><TMPL_VAR contest_name><a>
  <TMPL_ELSE><TMPL_VAR contest_name></TMPL_IF>
</td></TMPL_LOOP></tr>
<tr><th>Задача</th><TMPL_LOOP sources_info><td>
  <TMPL_IF href_problem><a href="<TMPL_VAR href_problem>"><TMPL_VAR problem_name></a>
  <TMPL_ELSE><TMPL_VAR problem_name></TMPL_IF>
</td></TMPL_LOOP></tr>
<tr><th>Набор тестов</th><TMPL_LOOP sources_info>
<td><TMPL_IF is_jury>
  <form action="<TMPL_VAR href_run_details>" method="POST" class="embedded">
  <input type="text" name="testsets" value="<TMPL_VAR testsets>" />
  <input type="submit" name="retest" value="Перетестировать" class="button" />
  </form>
<TMPL_ELSE><TMPL_VAR testsets></TMPL_IF></td>
</TMPL_LOOP></tr>
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
<TMPL_IF ignore_submit>Ignored submission</TMPL_IF>
</td></TMPL_LOOP>
</tr>
<tr><th>Ссылки</th>
<TMPL_LOOP sources_info><td>
<a href="<TMPL_VAR href_view_source>" class="<TMPL_VAR href_class_view_source>">код</a> |
<a href="<TMPL_VAR href_download_source>" class="<TMPL_VAR href_class_download_source>">скачать</a> |
<a href="<TMPL_VAR href_run_details>" class="<TMPL_VAR href_class_run_details>">результаты</a> |
<a href="<TMPL_VAR href_diff_runs>" class="<TMPL_VAR href_class_diff_runs>">diff</a>
<TMPL_IF is_jury> | <a href="<TMPL_VAR href_run_log>" class="<TMPL_VAR href_class_run_log>">лог</a></TMPL_IF>
</td></TMPL_LOOP>
</tr>
</table>
