@rem = '
@setlocal EnableDelayedExpansion
@set CATS_ROOT=%~dp0
@if %CATS_ROOT:~-1%==\ SET CATS_ROOT=%CATS_ROOT:~0,-1%
@set RUNNER=%0
@set CPAN_PACKAGES=DBI Algorithm::Diff SQL::Abstract JSON::XS YAML::Syck Apache2::Request XML::Parser::Expat Template
@set CPAN_FORCE_PACKAGES=DBD::Firebird Text::Aspell Archive::Zip 

@echo %CATS_ROOT%
::@call :install_perl_modules
::@call :create_symbolic_links

@call :find_dir Apache2
@set apache2_dir=%_result%
@call :find_dir strawberry
@set perl_dir=%_result%
@call :find_visual_studio
@set vs_dir=%_result%
@call :get_firebird_path
@set fb_dir=%_result%

@call :create_symbolic_links
@call :compile_udf
@call :install_aspell_dev
@call :install_mod_perl
@call :install_perl_modules
@call :config_apache

@rem Disabled
::@pushd docs
::ttree -a
::@popd ..

@call :cats_setup


@goto :eof

:download_file 
@setlocal
	@perl -x -S %RUNNER% %1 %2

	@goto :endofdownload

	@rem ';
#!perl

use strict;
use warnings;

use LWP::Simple;

getstore($ARGV[0], $ARGV[1]);
1;
__END__
:endofdownload
@endlocal
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
	@for %%x in (Microsoft\VisualStudio\SxS\VS7 Wow6432Node\Microsoft\VisualStudio\SxS\VS7) do @(
		@for %%r in (HKLM HKCU) do @(
			@for /F "tokens=1,2*" %%i in ('reg query "%%r\SOFTWARE\%%x" /v "11.0"') DO @(
				@for %%v in (16.0 15.0 14.0 13.0 12.0 11.0 10.0 9.0) do @(
					@if "%%i"=="%%v" @(
						@SET "vs_path=%%k"
						@goto :GetVSCommonToolsDirHelper_end
					)
				)
			)
		)
	)
	:GetVSCommonToolsDirHelper_end
	@if "%vs_path%"=="" exit /B 1
	@SET "vs_path=%vs_path%VC\bin\"
@endlocal & set _result=%vs_path%
@goto :eof


:compile_udf
@setlocal
	@pushd sql
	@pushd interbase
	@pushd UDF
	@set IBASE_PATH=%fb_dir%
	@call "%vs_dir%vcvars32.bat" > nul
	@call "%vs_dir%nmake.exe" /f Makefile.win32
	@cp cats_udf_lib.dll "%fb_dir%\lib"
	@popd
	@popd
	@popd
@endlocal
@goto :eof


:create_symbolic_links
@setlocal
	@rm images
	@rm docs
	@mklink /D images template\std\images
	@mklink /D docs templates\std\docs
@endlocal
@goto :eof

:find_dir
@setlocal
	@set result=""
	@set /p find_automatically=Find %1 automatically?[y/n]: 
	@if "%find_automatically%" EQU "n" (
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
			@if "!is_found!" EQU "y" (
				set result=%%p:\%1
				goto :end_search
			)
		)
	)
	:end_search

@endlocal & set _result=%result%
@goto :eof

:install_aspell_dev
@setlocal
	@echo "*** Installing Aspell"
	@set ASPELL="http://ftp.gnu.org/gnu/aspell/w32/aspell-dev-0-50-3-3.zip"
	@call :download_file %ASPELL% aspell.zip
	@call unzip aspell.zip
	@pushd aspell-dev-0-50-3-3
		@pushd lib
		@for %%s in (*-15*) do @(
		  @set name=%%s
		  @call rename %%name%% %%name:-15=%%
		)
		@popd
		@call cp -r include %perl_dir%\c\
		@call cp -r lib %perl_dir%\c\
	@popd
	@rm aspell.zip
	@rm -rf aspell-dev-0-50-3-3
@endlocal
@goto :eof

:install_mod_perl
@setlocal
	@echo "*** Installing mod_perl"
	@set MOD_PERL="http://people.apache.org/~stevehay/mod_perl-2.0.8-strawberryperl-5.16.3.1-32bit.zip"
	@call :download_file %MOD_PERL% mod_perl.zip
	@call unzip -d mod_perl mod_perl.zip
	@pushd mod_perl
	@cp -r Apache2\* %Apache2_dir%\
	@cp -r Strawberry\* %Perl_dir%\
	@popd
	@rm mod_perl.zip
	@rm -rf mod_perl
@endlocal
@goto :eof

:install_perl_modules
@setlocal
	@echo "Installing perl modules"
	@call cpanm %CPAN_PACKAGES%
	@call cpanm -f %CPAN_FORCE_PACKAGES%
	exit
	@echo "Downloading perl modules"
	@set formal_input="https://github.com/downloads/klenin/cats-main/FormalInput.tgz"
	call :download_file %formal_input% fi.tgz
	bsdtar -xzvf fi.tgz
	@pushd FormalInput
		perl Makefile.PL
		dmake
		dmake install
	popd
	@rm fi.tgz
	@rm -rf FormalInput

@endlocal
@goto :eof


:config_apache
@setlocal

	set CATS_ROOT=%CATS_ROOT:\=/%

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

	@echo !APACHE_CONF! > %Apache2%\conf\extra\httpd-vhosts.conf


@endlocal
@goto :eof


:cats_setup
@setlocal
	@set CONNECT_NAME=Connect.pm
	@set CONNECT_ROOT=%CATS_ROOT%\cgi-bin\CATS
	@set CREATE_DB_NAME=create_db.sql
	@set CREATE_DB_ROOT=%CATS_ROOT%\sql\interbase

	@set CONNECT="%CONNECT_ROOT%\%CONNECT_NAME%"
	@cp "%CONNECT_ROOT%\%CONNECT_NAME%.template" %CONNECT%

	@set CREATE_DB="%CREATE_DB_ROOT%\%CREATE_DB_NAME%"
	@cp "%CREATE_DB_ROOT%\%CREATE_DB_NAME%.template" %CREATE_DB%

	@echo ...
	@echo ...
	@echo ...

	@set answer=
	:loop_answer
		@if "%answer%" equ "y" goto :done_answer 
		@if "%answer%" equ "n" goto :done_answer
	   	@set /p answer=Do you want to do the automatic setup? 
	   	@goto :loop_answer
	:done_answer

	@if "%answer%" equ "n" (
	   @echo Setup is done, you need to do following manualy:\n
	   @echo  1. Navigate to %CONNECT_ROOT%\
	   @echo  2. Adjust your database connection settings in %CONNECT_NAME%
	   @echo  3. Navigate to %CREATE_DB_ROOT%
	   @echo  4. Adjust your database connection settings in %CREATE_DB_NAME% and create database\n
	   @exit 0
	)

	@set /p path_to_db=path-to-your-database: 
	@set /p db_host=your-host: 
	@set /p db_user=your-db-username: 
	@set /p db_pass=your-db-password: 

	@set path_to_db=%path_to_db:\=\\%

	@sed -i -e "s/<path-to-your-database>/%path_to_db%/g" %CONNECT%
	@sed -i -e "s/<your-host>/%db_host%/g" %CONNECT%
	@sed -i -e "s/<your-username>/%db_user%/g" %CONNECT%
	@sed -i -e "s/<your-password>/%db_pass%/g" %CONNECT%

	@sed -i -e "s/<path-to-your-database>/%path_to_db%/g" %CREATE_DB%
	@sed -i -e "s/<your-username>/%db_user%/g" %CREATE_DB%
	@sed -i -e "s/<your-password>/%db_pass%/g" %CREATE_DB%
	@rm sed*

@endlocal
@goto :eof


@endlocal
