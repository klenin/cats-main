package cats;

#$htdocs = "http://imcs.dvgu.ru/acm/cats/docs";
$htdocs = "./docs";
$flags_path = "./images/std/countries/";

$anonymous_login = 'anonymous';

# путь к шаблонам
@templates = (
    { id => "std", path => "./../templates/std" },
    { id => "alt", path => "./../templates/alt" }
);


# максимальное количество записей, извлекаемых из датасета
$max_fetch_row_count = 1000;

# скорость обновления
$refresh_rate = 30;

# количество отображаемых страниц
$visible_pages = 5;

# количество отображаемых строк с списке
@display_rows = ( 10, 20, 30, 40, 50, 100, 300 );

# роль пользователя в системе
$srole_root = 0; # администратор системы
$srole_user = 1; # пользователь системы
$srole_contests_creator = 2; # может создавать турниры

# типы исходников, в таблице problem_sources
$generator = 0;
$solution = 1;
$checker = 2;
$adv_solution = 3;
$generator_module = 4;
$solution_module = 5;
$checker_module = 6;
$testlib_checker = 7;
$partial_checker = 8;

%source_module_names = (
    $generator => 'generator',
    $solution => 'solution',
    $checker => 'checker (deprecated)',
    $adv_solution => 'solution (autorun)',
    $generator_module => 'generator module',
    $solution_module => 'solution module',
    $checker_module => 'checker module',
    $testlib_checker => 'checker',
    $partial_checker => 'partial checker',
);

# типы модулей для исходников
%source_modules = (
    $generator => $generator_module,
    $solution => $solution_module,
    $adv_solution => $solution_module,
    $checker => $checker_module,
    $testlib_checker => $checker_module,
    $partial_checker => $checker_module,
);

# состояние запроса в очереди
$st_not_processed = 0;
$st_unhandled_error = 1;
$st_install_processing = 2;
$st_testing = 3;

$request_processed = 9;

$st_accepted = 10;
$st_wrong_answer = 11;
$st_presentation_error = 12;
$st_time_limit_exceeded = 13;
$st_runtime_error = 14;
$st_compilation_error = 15;
$st_security_violation = 16;
$st_memory_limit_exceeded = 17;
$st_ignore_submit = 18;

$problem_st_ready     = 0;
$problem_st_suspended = 1;
$problem_st_disabled  = 2;
$problem_st_hidden    = 3;

# сигналы судье
$js_nosig = 0;
$js_kill = 1;

# типы сообщений
$msg_que = 0;
$msg_ans = 1;
$msg_msg = 2;

$penalty = 20;

$slow_refresh = 30;
$medium_refresh = 10;
$fast_refresh = 3;

@skins = (
    { id => "std", path => "./../templates/std" },
    { id => "alt", path => "./../templates/alt" }
);

@countries = (

{ id => "xx", name => "I'm an alien intellect", flag => "al.gif" },
{ id => "AI", name => "ANGUILLA",       flag => "ai.gif" },
{ id => "AQ", name => "ANTARCTICA",     flag => undef },
{ id => "AR", name => "ARGENTINA",      flag => "ar.gif" },
{ id => "AM", name => "ARMENIA",        flag => "am.gif" },
{ id => "AU", name => "AUSTRALIA",      flag => "au.gif" },
{ id => "AT", name => "AUSTRIA",        flag => "at.gif" },
{ id => "AZ", name => "AZERBAIJAN",     flag => "az.gif" },
{ id => "BH", name => "BAHRAIN",        flag => "bh.gif" },
{ id => "BD", name => "BANGLADESH",     flag => "bd.gif" },
{ id => "BY", name => "BELARUS",        flag => "by.gif" },
{ id => "BE", name => "BELGIUM",        flag => "be.gif" },
{ id => "BO", name => "BOLIVIA",        flag => "bo.gif" },
{ id => "BA", name => "BOSNIA AND HERZEGOWINA", flag => "ba.gif" },
{ id => "BR", name => "BRAZIL", flag => "br.gif" },
{ id => "BG", name => "BULGARIA",       flag => "bg.gif" },
{ id => "CA", name => "CANADA", flag => "ca.gif" },
{ id => "TD", name => "CHAD",   flag => "td.gif" },
{ id => "CL", name => "CHILE",  flag => "cl.gif" },
{ id => "CN", name => "CHINA",  flag => "cn.gif" },
{ id => "CX", name => "CHRISTMAS ISLAND",       flag => undef },
{ id => "CO", name => "COLOMBIA",       flag => "co.gif" },
{ id => "CK", name => "COOK ISLANDS",   flag => "ck.gif" },
{ id => "HR", name => "CROATIA",        flag => "hr.gif" },
{ id => "CU", name => "CUBA",   flag => "cu.gif" },
{ id => "CY", name => "CYPRUS", flag => "cy.gif" },
{ id => "CZ", name => "CZECH REPUBLIC", flag => "cz.gif" },
{ id => "DK", name => "DENMARK",        flag => "dk.gif" },
{ id => "DO", name => "DOMINICAN REPUBLIC",     flag => "do.gif" },
{ id => "EG", name => "EGYPT",  flag => "eg.gif" },
{ id => "SV", name => "EL SALVADOR",    flag => "sv.gif" },
{ id => "EE", name => "ESTONIA",        flag => "ee.gif" },
{ id => "FI", name => "FINLAND",        flag => "fi.gif" },
{ id => "FR", name => "FRANCE", flag => "fr.gif" },
{ id => "GE", name => "GEORGIA",        flag => "ge.gif" },
{ id => "DE", name => "GERMANY",        flag => "de.gif" },
{ id => "GR", name => "GREECE", flag => "gr.gif" },
{ id => "GT", name => "GUATEMALA",      flag => "gt.gif" },
{ id => "HN", name => "HONDURAS",       flag => "hn.gif" },
{ id => "HK", name => "HONG KONG",      flag => "hk.gif" },
{ id => "HU", name => "HUNGARY",        flag => "hu.gif" },
{ id => "IN", name => "INDIA",  flag => "in.gif" },
{ id => "ID", name => "INDONESIA",      flag => "id.gif" },
{ id => "IR", name => "IRAN (ISLAMIC REPUBLIC OF)",     flag => "ir.gif" },
{ id => "IE", name => "IRELAND",        flag => "ie.gif" },
{ id => "IL", name => "ISRAEL", flag => "il.gif" },
{ id => "IT", name => "ITALY",  flag => "it.gif" },
{ id => "JM", name => "JAMAICA",        flag => "jm.gif" },
{ id => "JP", name => "JAPAN",  flag => "jp.gif" },
{ id => "KZ", name => "KAZAKHSTAN",     flag => "kz.gif" },
{ id => "KP", name => "KOREA, DEMOCRATIC PEOPLE'S REPUBLIC OF", flag => "kp.gif" },
{ id => "KR", name => "KOREA, REPUBLIC OF",     flag => "kr.gif" },
{ id => "KW", name => "KUWAIT", flag => "kw.gif" },
{ id => "KG", name => "KYRGYZSTAN",     flag => "kg.gif" },
{ id => "LA", name => "LAO PEOPLE'S DEMOCRATIC REPUBLIC",       flag => "la.gif" },
{ id => "LV", name => "LATVIA", flag => "lv.gif" },
{ id => "LY", name => "LIBYAN ARAB JAMAHIRIYA", flag => "ly.gif" },
{ id => "LT", name => "LITHUANIA",      flag => "lt.gif" },
{ id => "LU", name => "LUXEMBOURG",     flag => "lu.gif" },
{ id => "MO", name => "MACAU",  flag => "mo.gif" },
{ id => "MK", name => "MACEDONIA",      flag => "mk.gif" },
{ id => "MY", name => "MALAYSIA",       flag => "my.gif" },
{ id => "MV", name => "MALDIVES",       flag => "mv.gif" },
{ id => "MX", name => "MEXICO", flag => "mx.gif" },
{ id => "MA", name => "MOROCCO",        flag => "ma.gif" },
{ id => "MZ", name => "MOZAMBIQUE",     flag => "mz.gif" },
{ id => "NP", name => "NEPAL",  flag => "np.gif" },
{ id => "NL", name => "NETHERLANDS",    flag => "nl.gif" },
{ id => "AN", name => "NETHERLANDS ANTILLES",   flag => "an.gif" },
{ id => "NZ", name => "NEW ZEALAND",    flag => "nz.gif" },
{ id => "NI", name => "NICARAGUA",      flag => "ni.gif" },
{ id => "NG", name => "NIGERIA",        flag => "ng.gif" },
{ id => "NO", name => "NORWAY", flag => "no.gif" },
{ id => "OM", name => "OMAN",   flag => "om.gif" },
{ id => "PK", name => "PAKISTAN",       flag => "pk.gif" },
{ id => "PY", name => "PARAGUAY",       flag => "py.gif" },
{ id => "PH", name => "PHILIPPINES",    flag => "ph.gif" },
{ id => "PL", name => "POLAND", flag => "pl.gif" },
{ id => "PT", name => "PORTUGAL",       flag => "pt.gif" },
{ id => "PR", name => "PUERTO RICO",    flag => "pr.gif" },
{ id => "RO", name => "ROMANIA",        flag => "ro.gif" },
{ id => "RU", name => "RUSSIAN FEDERATION",     flag => "ru.gif" },
{ id => "SM", name => "SAN MARINO",     flag => "sm.gif" },
{ id => "SG", name => "SINGAPORE",      flag => "sg.gif" },
{ id => "SK", name => "SLOVAKIA (Slovak Republic)",     flag => "sk.gif" },
{ id => "SI", name => "SLOVENIA",       flag => "si.gif" },
{ id => "ZA", name => "SOUTH AFRICA",   flag => "za.gif" },
{ id => "ES", name => "SPAIN",  flag => "es.gif" },
{ id => "SE", name => "SWEDEN", flag => "se.gif" },
{ id => "CH", name => "SWITZERLAND",    flag => "ch.gif" },
{ id => "TW", name => "TAIWAN", flag => "tw.gif" },
{ id => "TZ", name => "TANZANIA, UNITED REPUBLIC OF",   flag => "tz.gif" },
{ id => "TH", name => "THAILAND",       flag => "th.gif" },
{ id => "TT", name => "TRINIDAD AND TOBAGO",    flag => "tt.gif" },
{ id => "TR", name => "TURKEY", flag => "tr.gif" },
{ id => "TM", name => "TURKMENISTAN",   flag => undef },
{ id => "UA", name => "UKRAINE",        flag => "ua.gif" },
{ id => "AE", name => "UNITED ARAB EMIRATES",   flag => "ae.gif" },
{ id => "UK", name => "UNITED KINGDOM", flag => "uk.gif" },
{ id => "US", name => "UNITED STATES",  flag => "us.gif" },
{ id => "UY", name => "URUGUAY",        flag => "uy.gif" },
{ id => "UZ", name => "UZBEKISTAN",     flag => "uz.gif" },
{ id => "VE", name => "VENEZUELA",      flag => "ve.gif" },
{ id => "VN", name => "VIET NAM",       flag => "vn.gif" },
{ id => "EH", name => "WESTERN SAHARA", flag => "eh.gif" },
{ id => "YU", name => "YUGOSLAVIA",     flag => "yu.gif" },
{ id => "ZW", name => "ZIMBABWE",       flag => "zw.gif" }

);

1;                                          
