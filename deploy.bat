@rem = '

@set version=0.1
@echo Automatic CATS Installer: version %version%
@echo[
@setlocal EnableDelayedExpansion
@set CATS_ROOT=%~dp0
@if %CATS_ROOT:~-1%==\ SET CATS_ROOT=%CATS_ROOT:~0,-1%
@set RUNNER=%0
@set CPAN_PACKAGES=DBI Algorithm::Diff SQL::Abstract JSON::XS YAML::Syck Apache2::Request XML::Parser::Expat Template
@set CPAN_FORCE_PACKAGES=DBD::Firebird Text::Aspell Archive::Zip 

@echo This script will automatically install CATS server on current machine.
@echo Consult with install.md if you having any problems with installing.
@echo[
@echo CATS root is set to %CATS_ROOT%
@echo[

@echo Looking for installed distributions...
@echo[
@call :find_dir Apache2
@set apache2_dir=%_result%
@call :find_dir strawberry
@set perl_dir=%_result%
@call :find_visual_studio
@set vs_dir=%_result%
@call :get_firebird_path
@set fb_dir=%_result%

@echo ==================================================
@call :check_pathes
@echo[
@if errorlevel 1 (
	@call :footer Exiting...
	@pause
	@goto :eof
) else call :footer Successfull

@call :create_symbolic_links
@echo[
@if errorlevel 1 (
	@call :footer Failed to Create symbolic links^! Create them manually or just copy required directories.>&2
	@pause
) else call :footer Successfull

@call :compile_udf
@echo[
@if errorlevel 1 (
	@call :footer Failed to compile UDF! Exiting...>&2
	@pause
	@goto :eof
) else call :footer Successfull

@call :install_aspell_dev
@echo[
@if errorlevel 1 (
	@call :footer Failed to install libaspell-dev! Exiting...>&2
	@pause
	@goto :eof
) else call :footer Successfull

@call :install_mod_perl
@echo[
@if errorlevel 1 (
	@call :footer Failed to install mod_perl! Exiting...>&2
	@pause
	@goto :eof
) else call :footer Successfull

@call :install_perl_modules
@echo[
@if errorlevel 1 (
	@call :footer Failed to install perl modules! Exiting...>&2
	@pause
	@goto :eof
) else call :footer Successfull

@echo Assuming that current directory is server root.
@echo[
@call :config_apache
@if errorlevel 1 (
	@call :footer Failed to config Apache2! Exiting...>&2
	@pause
	@goto :eof
) else call :footer Successfull

@call :cats_setup
@echo[
@if errorlevel 1 (
	@call :footer Failed to configure CATS! Exiting...>&2
	@pause
	@goto :eof
) else call :footer Successfull
@rem Disabled
::@pushd docs
::ttree -a
::@popd ..


@echo Installation completed
@echo Check install.md for further instructions.
@pause



@goto :eof


:footer
@echo %*
@echo ==================================================
@goto :eof

:check_path
@setlocal
	@if "%~1" == "" @set "error_text=Empty path specified"
	@if "%~1" neq "" if not exist "%~1" set "error_text=Invalid path specified"
	@if "%error_text%" neq "" (
		@echo %~2: %error_text%>&2
		@endlocal
		@exit /B 1
	)
@endlocal
@goto :eof

:check_pathes
@setlocal
	@echo Checking provided distributions folders
	@rem Simple path chech
	@rem TODO make it more advanced with actual program check

	@set error=0

	@call :check_path "%apache2_dir%" "No proper Apache2 installation found"
	@if errorlevel 1 set error=1
	@call :check_path "%perl_dir%" "No proper Strawberry Perl installation found"
	@if errorlevel 1 set error=1
	@call :check_path "%fb_dir%" "No proper Firebird installation found"
	@if errorlevel 1 set error=1
	@call :check_path "%vs_dir%" "No proper Visual Studio installation found"
	@if errorlevel 1 set error=1	

	@if %error% == 1 exit /B 1
@endlocal
@goto :eof

:download_file 
@setlocal
	@call :utilize_perl "download" %1 %2
@endlocal
@goto :eof


:extract_file 
@setlocal
	@call :utilize_perl "extract" %1 %2
@endlocal
@goto :eof


:utilize_perl 
@setlocal
	@perl -x -S %RUNNER% %1 %2 %3

	@goto :endofdownload

	@rem ';
#!perl

use strict;
use warnings;

use LWP::Simple;
use Archive::Extract;

sub download {
	my ($what, $where) = @_;
	getstore($what, $where);
}
sub extract {
	my ($what, $where) = @_;
	my $ae = Archive::Extract->new( archive => $what );
	if (!$where || $where eq "") {
		$ae->extract or die $ae->error;
		return;
	}
	$ae->extract( to => $where );	
}
if ($ARGV[0] eq "download") {
	download($ARGV[1], $ARGV[2]);
} elsif ($ARGV[0] eq "extract") {
	extract($ARGV[1], $ARGV[2]);
} elsif ($ARGV[0] eq "sed") {
	extract($ARGV[1], $ARGV[2]);
}
1;
__END__
:endofdownload
@endlocal
@goto :eof

:find_dir
@setlocal
	@set result=
	@set /p find_automatically=Find %1 automatically?[y/n]: 
	@if "%find_automatically%" == "n" (
		@set /p result="Enter directory for %1 manually: "
	@goto :end_search
	) else (
		@if "%find_automatically%" NEQ "y" (
			@goto :end_search
		)
	)
	@for %%p in (B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do @(
		@if exist %%p:\%1 (
			set /p is_found=Is "%%p:\%1" correct?[y/n]: 
			@if "!is_found!" == "y" (
				set result=%%p:\%1
				goto :end_search
			)
		)
	)
	:end_search

@endlocal & set _result=%result%
@goto :eof


:get_firebird_path
@setlocal
	@set /p result=Specify Firebird path(Default is - D:\Program Files (x86)\Firebird\Firebird_2_5\): 
	@if "%result%" == "" set result=D:\Program Files (x86)\Firebird\Firebird_2_5\
	@IF %result:~-1%==\ SET result=%result:~0,-1%
@endlocal & set _result=%result%
@goto :eof

:find_visual_studio
@setlocal
	@echo Looking for Visual Studio installed...
	@for %%x in (Microsoft\VisualStudio\SxS\VS7 Wow6432Node\Microsoft\VisualStudio\SxS\VS7) do @(
		@for %%r in (HKLM HKCU) do @(
			@for /F "tokens=1,2*" %%i in ('reg query "%%r\SOFTWARE\%%x" /v "11.0"') DO @(
				@for %%v in (16.0 15.0 14.0 13.0 12.0 11.0 10.0 9.0) do @(
					@if "%%i"=="%%v" @(
						@echo =^>Visual Studio %%v detected
						@echo =^>Using Visual Studio %%v toolchain
						@SET "vs_path=%%k"
						@goto :GetVSCommonToolsDirHelper_end
					)
				)
			)
		)
	)
	:GetVSCommonToolsDirHelper_end
	@if "%vs_path%"=="" @exit /B 1
	@SET "vs_path=%vs_path%VC\bin\"
@endlocal & set _result=%vs_path%
@goto :eof


:compile_udf
@setlocal
	@echo Compiling UDF module for Firebird with Visual Studio toolchain...
	@pushd sql
	@pushd interbase
	@pushd UDF
	@set IBASE_PATH=%fb_dir%
	@call "%vs_dir%vcvars32.bat" > nul
	@call "%vs_dir%nmake.exe" /f Makefile.win32
	@if not exist "%CATS_ROOT%\sql\interbase\UDF\cats_udf_lib.dll" exit /B 1
	@echo Compilation successfull!
	@copy cats_udf_lib.dll "%fb_dir%\lib" > nul
	@popd
	@popd
	@popd
@endlocal
@goto :eof


:create_symbolic_links
@setlocal
	@echo Creating symbolic links to directories...
	@del /Q images > nul
	@del /Q docs > nul
	@mklink /D images template\std\images
	@mklink /D docs templates\std\docs
@endlocal
@goto :eof


:install_aspell_dev
@setlocal
	@echo Installing libaspell-dev...
	@set ASPELL="http://ftp.gnu.org/gnu/aspell/w32/aspell-dev-0-50-3-3.zip"
	@call :download_file %ASPELL% aspell.zip
	@call :extract_file aspell.zip
	@pushd aspell-dev-0-50-3-3
		@pushd lib
		@for %%s in (*-15*) do @(
		  @set name=%%s
		  @call rename %%name%% %%name:-15=%%
		)
		@popd
		@call xcopy include %perl_dir%\c\ /e/y/i/g/h/k > nul
		@call xcopy lib %perl_dir%\c\ /e/y/i/g/h/k > nul
	@popd
	@del aspell.zip > nul
	@rmdir aspell-dev-0-50-3-3 /S /Q > nul
@endlocal
@goto :eof

:install_mod_perl
@setlocal
	@echo Installing mod_perl...
	@set MOD_PERL="http://people.apache.org/~stevehay/mod_perl-2.0.8-strawberryperl-5.16.3.1-32bit.zip"
	@call :download_file %MOD_PERL% mod_perl.zip
	@call :extract_file mod_perl.zip mod_perl
	@pushd mod_perl
		@xcopy Apache2\* %Apache2_dir%\ /e/y/i/g/h/k > nul
		@xcopy Strawberry\* %Perl_dir%\ /e/y/i/g/h/k > nul
	@popd
	@del mod_perl.zip > nul
	@rmdir mod_perl /S /Q > nul
@endlocal
@goto :eof

:install_perl_modules
@setlocal
	@echo Installing perl modules...
	@call cpanm %CPAN_PACKAGES%
	@call cpanm -f %CPAN_FORCE_PACKAGES% 
	@echo Downloading external perl modules...
	@set formal_input="https://github.com/downloads/klenin/cats-main/FormalInput.tgz"
	@call :download_file %formal_input% fi.tgz
	@call :extract_file fi.tgz
	@pushd FormalInput
		@perl Makefile.PL
		@dmake
		@dmake install
	@popd
	@del fi.tgz > nul
	@rmdir FormalInput /S /Q > nul

@endlocal
@goto :eof


:config_apache
@setlocal
	@echo Configuring Apache2...
	@echo Writing to conf\extra\httpd-vhosts.conf

	@set CATS_ROOT=%CATS_ROOT:\=/%

	@set APACHE_CONF=PerlSetEnv CATS_DIR %CATS_ROOT%/cgi-bin/^

^<VirtualHost *:80^>^

	PerlRequire %CATS_ROOT%/cgi-bin/CATS/Web/startup.pl^

	^<Directory "%CATS_ROOT%/cgi-bin/"^>^

		Options -Indexes +FollowSymLinks^

		DirectoryIndex main.pl^

		LimitRequestBody 1048576^

		AllowOverride all^

		Order allow,deny^

		Allow from all^

		^<Files "main.pl"^>^

			# Apache 2.x / ModPerl 2.x specific^

			PerlResponseHandler main^

			PerlSendHeader On^

			SetHandler perl-script^

		^</Files^>^

	^</Directory^>^

^

	ExpiresActive On^

	ExpiresDefault "access plus 5 seconds"^

	ExpiresByType text/css "access plus 1 week"^

	ExpiresByType application/javascript "access plus 1 week"^

	ExpiresByType image/gif "access plus 1 week"^

	ExpiresByType image/x-icon "access plus 1 week"^

^

	Alias /cats/static/ "%CATS_ROOT%/static/"^

	^<Directory "%CATS_ROOT%/static"^>^

		# Apache allows only absolute URL-path^

		ErrorDocument 404 /cats/main.pl?f=static^

		#Options FollowSymLinks^

		AddDefaultCharset utf-8^

	^</Directory^>^

^

	Alias /cats/docs/ "%CATS_ROOT%/docs/"^

	^<Directory "%CATS_ROOT%/docs"^>^

		AddDefaultCharset utf-8^

	^</Directory^>^

^

	Alias /cats/ev/ "%CATS_ROOT%/ev/"^

	^<Directory "%CATS_ROOT%/ev"^>^

		AddDefaultCharset utf-8^

	^</Directory^>^

^

	^<Directory "%CATS_ROOT%/docs/std/"^>^

		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo^

		Order allow,deny^

		Allow from all^

	^</Directory^>^

^

	^<Directory "%CATS_ROOT%/images/std/"^>^

		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo^

		Order allow,deny^

		Allow from all^

	^</Directory^>^

^

	Alias /cats/synh/ "%CATS_ROOT%/synhighlight/"^

	Alias /cats/images/ "%CATS_ROOT%/images/"^

	Alias /cats/ "%CATS_ROOT%/cgi-bin/"^

^</VirtualHost^>

	@echo !APACHE_CONF! > %Apache2_dir%\conf\extra\httpd-vhosts.conf
	@echo Check install.md for further instructions on configuring Apache2


@endlocal
@goto :eof


:cats_setup
@setlocal
	@echo Configuring CATS...
	@set CONNECT_NAME=Connect.pm
	@set CONNECT_ROOT=%CATS_ROOT%\cgi-bin\CATS
	@set CREATE_DB_NAME=create_db.sql
	@set CREATE_DB_ROOT=%CATS_ROOT%\sql\interbase

	@set CONNECT="%CONNECT_ROOT%\%CONNECT_NAME%"
	@copy "%CONNECT_ROOT%\%CONNECT_NAME%.template" %CONNECT% > nul

	@set CREATE_DB="%CREATE_DB_ROOT%\%CREATE_DB_NAME%"
	@copy "%CREATE_DB_ROOT%\%CREATE_DB_NAME%.template" %CREATE_DB% > nul 

	@echo[
	@echo[
	@echo[

	@set answer=
	:loop_answer
		@if "%answer%" equ "y" goto :done_answer 
		@if "%answer%" equ "n" goto :done_answer
	   	@set /p answer=Do you want to do the automatic setup?[y/n] 
	   	@goto :loop_answer
	:done_answer

	@if "%answer%" equ "n" (
	   @echo Setup is done, you need to do following manualy:
	   @echo  1. Navigate to %CONNECT_ROOT%\
	   @echo  2. Adjust your database connection settings in %CONNECT_NAME%
	   @echo  3. Navigate to %CREATE_DB_ROOT%\
	   @echo  4. Adjust your database connection settings in %CREATE_DB_NAME% and create database
	   @exit 0
	)

	@set /p path_to_db=Specify path to database [%CATS_ROOT%\ib_data\cats.gdb]: 
	@set /p db_host=Specify host for database [localhost]: 
	@set /p db_user=Specify username for database [sysdba]: 
	@set /p db_pass=Specify password for database [masterkey]: 
	@if "%path_to_db%"=="" set path_to_db=%CATS_ROOT%\ib_data\cats.gdb
	@if "%db_host%"=="" set db_host=localhost
	@if "%db_user%"=="" set db_user=sysdba
	@if "%db_pass%"=="" set db_pass=masterkey

	@if not exist "%path_to_db%" echo You'll need to create %path_to_db% manually.

	@set path_to_db=%path_to_db:\=\\\\%

	@sed -i -e "s/<path-to-your-database>/%path_to_db%/g" %CONNECT%
	@sed -i -e "s/<your-host>/%db_host%/g" %CONNECT%
	@sed -i -e "s/<your-username>/%db_user%/g" %CONNECT%
	@sed -i -e "s/<your-password>/%db_pass%/g" %CONNECT%

	@sed -i -e "s/<path-to-your-database>/%path_to_db%/g" %CREATE_DB%
	@sed -i -e "s/<your-username>/%db_user%/g" %CREATE_DB%
	@sed -i -e "s/<your-password>/%db_pass%/g" %CREATE_DB%
	@rm sed*
	@echo Configuration written to %connect% and %create_db%.

@endlocal
@goto :eof


@endlocal
