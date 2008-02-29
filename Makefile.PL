require 5.000_000;
use ExtUtils::MakeMaker;
eval "use Devel::Required";

WriteMakefile (
 NAME		=> "OOB",
 AUTHOR		=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
 ABSTRACT	=> 'out of bounds data for any data structure in Perl',
 VERSION_FROM	=> 'lib/OOB.pm',
 PREREQ_PM	=> { qw(
                    Scalar::Util  1.14
                   ) },
);
