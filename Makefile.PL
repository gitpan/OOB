require 5.000_000;
use ExtUtils::MakeMaker;
eval "use Devel::Required";

WriteMakefile (
 NAME		=> "oob",
 AUTHOR		=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
 ABSTRACT	=> 'out of bounds data for any data structure in Perl',
 VERSION_FROM	=> 'lib/oob.pm',
 PREREQ_PM	=> { qw(
                    Scalar::Util  1.14
                   ) },
);
