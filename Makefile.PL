use inc::Module::Install;

name 'Config-Wild';
license 'gpl3';
all_from 'lib/Config/Wild.pm';

requires 'Lingua::Boolean::Tiny';

WriteAll;
