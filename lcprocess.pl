use strict;
use warnings;
use Getopt::Long qw (GetOptions);
use Pod::Usage qw (pod2usage);
use String::Random qw(random_string);
use File::BackupCopy qw(backup_copy_numbered);
use File::Copy;
use List::Util 'shuffle';
use v5.10;

my $man                            = 0;
my $help                           = 0;
my $helpHeader                     = 'Arguments required, see below\n';
my $nargs                          = @ARGV;
my $runWithNoArgsAllowed           = 0;
my $inf                            = '';
my $ouf                            = 'lco999.temp';
my $nobackup                       = '';
my $randomiseTrialOrderWithinPhase = '';
my $randomiseCueColours            = '';
my $randomiseCuePositions          = '';
my $randomiseFlashRate             = '';
my $randomiseContexts              = '';
my $allRandomisations              = '';
my $printVersion                   = '';
my $version                        = '0.1.0';

if ( !$nargs && !$runWithNoArgsAllowed ) {
	pod2usage(2);    #exit error 2 after printing SYNOPSIS, verbose 0
}

## Parse options and print usage if there is a syntax error,
## or if usage was explicitly requested.
GetOptions(
	'help|?'             => \$help,
	'man'                => \$man,
	'file=s'             => \$inf,
	'nobackup'           => \$nobackup,
	'trialRandomise'     => \$randomiseTrialOrderWithinPhase,
	'cueColourRandomise' => \$randomiseCueColours,
	'contextRandomise'   => \$randomiseContexts,
	'positionRandomise'  => \$randomiseCuePositions,
	'rateRandomise'      => \$randomiseFlashRate,
	'all'                => \$allRandomisations,
	'version'            => \$printVersion
) or pod2usage(2);
pod2usage(1)
  if $help;    #exit error 1 after printing SYNOPSIS and OPTIONS, verbose 1;
pod2usage( -verbose => 2 ) if $man;  #exit error 1 after printing man, verbose 2

if (
	$inf
	&& (
		!(
			   $randomiseCueColours
			|| $randomiseCuePositions
			|| $randomiseFlashRate
			|| $randomiseContexts
			|| $allRandomisations
		)
	)
  )
{
	say
"Option -f must be combined with one or more processing options (-t, -cu, -co, -p, -r, or -s)";
	exit;
}
if ($printVersion) {
	say "lcprocess.pl version: $version";
	exit;
}

#pod3usage verbosity 0 -> SYNOPSIS
#pod3usage verbosity 1 -> SYNOPSIS and OPTIONS, ARGUMENTS, or OPTIONS AND
#ARGUMENTS
#pod3usage verbosity 2 -> all sections
#see pod2usage, perlpod, and perlpodstyle
print("Running with $nargs arguments\n");
my $backupName = backup_copy_numbered($inf) unless $nobackup;

#functions
#call with trial number and trialLines hash reference e.g. cvtTL 0, \%trialLines
#returns a string for the specified trial extracted from %trialLines
#helper for randomiseTrials
sub cvtTL {
	my ( $t, $TL ) = @_;
	my $result =
		( split /\s+/, %$TL{'PHASE'} )[$t] . "\t"
	  . random_string("CCCC") . "\t"
	  . ( split /\s+/, %$TL{'CONTEXT'} )[$t] . "\t"
	  . ( split /\s+/, %$TL{'PRE'} )[$t] . "\t"
	  . ( split /\s+/, %$TL{'EVENT'} )[$t] . "\t"
	  . ( split /\s+/, %$TL{'ITI'} )[$t];
	return $result;
}

#call with trialLines hash reference e.g. randomiseTrials \%trialLines
#returns a randomised array of strings ready to be reformatted to the
#paramfile format. Each string has seven space separated fields
#PHASE sortKey CTX PRE EVENT ITI
#sortKey will be dropped to output
#helper for randomiseTrialsInPhase
sub randomiseTrials {
	my $TL = $_[0];
	my $nt = split /\s+/, %$TL{'Trial'};
	my @trialsToRandomise;
	for my $t ( 1 .. $nt ) {
		my $buff = cvtTL $t- 1, $TL;
		push @trialsToRandomise, $buff;
	}
	return sort(@trialsToRandomise);
}

#main function
sub randomiseTrialsInPhase {
	open my $infh, '<', $inf, or die "Cannot open $inf for reading : $! \n";
	open my $oufh, '>', $ouf, or die "Cannot open $ouf for writing : $! \n";
	my @trialElements =
	  ( "PHASE =\t", "SORT", "CONTEXT =", "PRE =\t", "EVENT =\t", "ITI =\t" );
	my @trialElementsOutputOrdering = (
		"Trial#\t\t",
		"ITI =\t",
		"PRE =\t",
		"EVENT =\t",
		"CONTEXT =",
		"PHASE =\t"
	);
	my $ntlines = 6; #number of rows for trials representation [Trial# .. PHASE]
	my $trialLineCounter = 0;
	my %trialLines
	  ; #a hash indexed by the keys [Trial..PHASE] to access the string value of each row, used for input and sorting
	my %trialLinesProcessed
	  ;    #%trialLines after trial order randomised within phase

	while (<$infh>) {
		chomp;
		if (/Trial#/) {
			$trialLineCounter++;
		}    #if (/Trial#/){
		if ( $trialLineCounter > 0 ) {
			my @buff = split /\s*#\s+|\s*=\s+/;
			$trialLines{ $buff[0] } = $buff[1];
			$trialLineCounter++;
			if ( $trialLineCounter > 6 ) {
				$trialLineCounter = 0;
				print "\n";
				my @randomisedTrials =
				  randomiseTrials \%trialLines;   #and write the new trial block
				my @AoA
				  ; #convert @randomisedTrials from array of strings to array of arrays, ready for a transpose operation
				foreach (@randomisedTrials) {
					my @buff = split /\s+/;
					push @AoA, [@buff];    #see perldoc perllol
				}
				my $nr = @AoA;             #number of rows (trials)
				my $nc = @{ $AoA[1] }
				  ; #number of cols (trial representation elements), including the sort key
				for ( my $j = 0 ; $j < $nc ; $j++ ) {    #loop over j columns
					my $info = "";
					for ( my $i = 0 ; $i < $nr ; $i++ ) {    #loop over i rows
						$info = $info . "\t" . $AoA[$i][$j];
					}    #for(my $i=0; $i<$nr; $i++){
					unless ( $j == 1 ) {    #we don't want the sort key
						$trialLinesProcessed{ $trialElements[$j] } =
						  $info;    #add the transpose col as string to hash
					}
				}    #for (my $j=0; $j<$nc; $j++){

				my $trialNumberString = "";
				foreach ( 1 .. $nr ) {
					$trialNumberString = $trialNumberString . $_ . "\t";
				}
				$trialLinesProcessed{"Trial#\t\t"} = $trialNumberString;
				foreach (@trialElementsOutputOrdering) {
					say $oufh "$_ $trialLinesProcessed{$_}";
				}
			}    #$trialLineCounter>6
		}    #if($trialLineCounter>0){
		else {
			say $oufh $_;  #need to write line if it's not part of a trial block
		}
	}    #while(<$infh>) {
	close $infh;
	close $oufh;
	copy( $ouf, $inf );
	unlink($ouf);
}    #sub randomiseTrialsInPhase{

#main function
#needs parameter 'col', 'pos', or 'rate' to select where randomisation applied
sub randomiseCSBlock {
	open my $infh, '<', $inf, or die "Cannot open $inf for reading : $! \n";
	open my $oufh, '>', $ouf, or die "Cannot open $ouf for writing : $! \n";

	my $nCSs        = 0;    #number of CSs
	my $lineCounter = 0;
	my %lines;
	my @preStrings;
	my @targetStrings;
	my @postStrings;
	my $type = shift;       #parameter

	my @preIdx =
		$type eq "col"  ? (0)
	  : $type eq "pos"  ? ( 0, 1, 2, 3, 4, 5 )
	  : $type eq "rate" ? ( 0, 1, 2, 3, 4, 5, 6 )
	  :                   die "wrong parameter passed to randomise CS: $type\n";

	my @targetIdx =
		$type eq "col"  ? ( 1, 2, 3 )
	  : $type eq "pos"  ? (6)
	  : $type eq "rate" ? (7)
	  :                   die "wrong parameter passed to randomise CS: $type\n";

	my @postIdx =
		$type eq "col"  ? ( 4, 5, 6, 7 )
	  : $type eq "pos"  ? (7)
	  : $type eq "rate" ? ()
	  :                   die "wrong parameter passed to randomise CS: $type\n";

	my $sepc =
		$type eq "col" ? ""
	  : $type eq "pos" ? ","
	  :                  ",";    # for output formatting on col, no comma
	my $sepr =
		$type eq "col" ? ","
	  : $type eq "pos" ? ","
	  :                  "";     # for output formatting on rate, no comma

	while (<$infh>) {

		chomp;

		if (/^CS DEFINITIONS/)
		{    #get the number of lines and flag the start of CS block
			my @buff = split /\s*=\s*/;
			$nCSs = $buff[1];
			$lineCounter++;
			@preStrings    = ();
			@targetStrings = ();
			@postStrings   = ();
			say $oufh $_;
		}    # if (/CS DEFINITIONS/) {
		if ( $lineCounter > 0 ) {    #we have a CS block
			unless (/^CS DEFINITIONS/)
			{ #process the CS block lines proper, ignoring CS header line, which has already been processed
				 #collect the lines into arrays pre, target, and post, the target will be sorted before rejoin and output
				my @buff = split /\s*=\s*|,\s*/;
				push @preStrings,    join ",", @buff[@preIdx];
				push @targetStrings, join ",", @buff[@targetIdx];
				push @postStrings,   join ",", @buff[@postIdx];
				$lineCounter++;
				if ( $lineCounter > 4 ) {    #CS block collected
					@targetStrings = shuffle(@targetStrings);
					for ( my $i = 0 ; $i < $nCSs ; $i++ ) {
						$preStrings[$i] =~
						  s/(^\w)(,*)/$1 = /; #remove , after CS, replace with =
						say $oufh
"$preStrings[$i]$sepc $targetStrings[$i]$sepr $postStrings[$i]";
					}
					$lineCounter = 0;         #reset waiting for next CS block
				}
			}    #unless (/CS DEFINITIONS/){#process the CS block lines proper
		}    #if ( $lineCounter > 0 ) {
		else {
			say $oufh $_;    #need to write line if it's not part of a CS block
		}
	}
	close $infh;
	close $oufh;
	copy( $ouf, $inf );
	unlink $ouf;
}    #sub randomiseColours{

#main function
sub randomiseContexts {
	open my $infh, '<', $inf, or die "Cannot open $inf for reading : $! \n";
	open my $oufh, '>', $ouf, or die "Cannot open $ouf for writing : $! \n";

	my $nCtx        = 0;
	my $lineCounter = 0;
	my @ctxStrings;

	while (<$infh>) {

		chomp;

		if (/^CONTEXT DEFINITIONS/)
		{    #get the number of lines and flag the start of CONTEXT block
			my @buff = split /\s*=\s*/;
			$nCtx = $buff[1];
			$lineCounter++;
			say $oufh $_;
			@ctxStrings = ();
		}    # if (/CONTEXT DEFINITIONS/) {
		if ( $lineCounter > 0 ) {    #we have a CONTEXT block
			unless (/^CONTEXT DEFINITIONS/)
			{ #process the CONTEXT block lines proper, ignoring CONTEXT header line, which has already been processed
				 #collect the lines into arrays pre, target, and post, the target will be sorted before rejoin and output
				my @buff = split /\s*=\s*/;
				if ( $buff[0] > 0 ) {
					push @ctxStrings, $buff[1];
				}
				else {
					say $oufh $_;    #not randomising training context
				}
				$lineCounter++;
				if ( $lineCounter > 4 ) {    #CONTEXT block collected
					@ctxStrings = shuffle(@ctxStrings);
					for ( my $i = 1 ; $i < $nCtx ; $i++ ) {
						say $oufh "$i = $ctxStrings[$i-1]";
					}
					$lineCounter = 0;    #reset waiting for next CONTEXT block
				}
			} #unless (/^CONTEXT DEFINITIONS/){#process the CONTEXT block lines proper
		}    #if ( $lineCounter > 0 ) {
		else {
			say $oufh $_
			  ;    #need to write line if it's not part of a CONTEXT block
		}
	}
	close $infh;
	close $oufh;
	copy( $ouf, $inf );
	unlink $ouf;
}

if ($randomiseTrialOrderWithinPhase) {
	randomiseTrialsInPhase;
}

if ($randomiseCueColours) {
	randomiseCSBlock "col";
}

if ($randomiseCuePositions) {
	randomiseCSBlock "pos";
}

if ($randomiseFlashRate) {
	randomiseCSBlock "rate";
}

if ($randomiseContexts) {
	randomiseContexts;
}

if ($allRandomisations) {
	randomiseTrialsInPhase;
	randomiseCSBlock "col";
	randomiseCSBlock "pos";
	randomiseCSBlock "rate";
	randomiseContexts;
}

if ($nobackup) {
	say "Done";
}
else {
	say "Done, original file backed up in $backupName";
}

say "All efforts made to ensure correct function but checking is imperative!";

__END__

=pod

=head1 NAME

lcprocess.pl - learning chicken parameter file processor

=head1 SYNOPSIS

examples:

   perl lcprocess.pl -t -f params.txt       		
   #trial order randomised within phase, output written to params.txt, old file backed up to parameters.txt.~N~
   
   perl lcprocess.pl -t -n -f params.txt    		
   #trial order randomised within phase, output written to params.txt, NO backup created!
   
   perl lcprocess.pl -cu -co -f params.txt  		
   #cue colour and context allocations randomised
   
   perl lcprocess.pl -t -cu -f params.txt -co -p 	
   #all randomisations
   
   perl lcprocess.pl -f params.txt -a -n 			
   #all randomisations, NO backup


 Options:
   -help                brief help message
   -man                 full documentation
   -file                parameter file to process, use with operation parameters below
   -trialRandomise      randomise trials within phase
   -cueColourRandomise  randomise cue colour allocations
   -positionRandomise   randomise cue position allocations
   -rateRandomise       randomise cue flash rate
   -contextRandomise    randomise context allocations
   -all                 all five randomisations
   -nobackup            don't create a backup, by default numbered backups produced

=head1 OPTIONS

=over 4

=item B<-help>

Helper program for learning chicken parameter file randomisations

=item B<-man>

This program needs a perl installation. It was developed and appears to work on Windows 10 
with Strawberry Perl v5.32.0 and should work anywhere as Perl is mostly portable. As well 
as a standard Perl installation this program depends on two CPAN modules. These can be 
installed by running cpan String::Random and cpan File::BackupCopy.

=back

=head1 DESCRIPTION

B<This program> will read the given input parameter file and will randomise the trial 
order (within phase) and/or cue colour allocations and/or cue positions and/or cue 
flash rates and/or context allocations in any combinations desired. 

Suggested usage for simple experiment: create one experimental condition manually. Copy
that n-times and then apply desired randomisations. Set CONDITIONS CONTAINED = n and 
CONDITION = 0. 

Suggested development: run lcprocess before starting learningchicken. That way there will
be no need to duplicate conditions in the parameter file that only differ in randomisation.

learning chicken experiment game developed by Dr. Byron Nelson

=head1 AUTHOR

Steven Glautier

=head1 COPYRIGHT

Copyright (C) 2019-21 Steven Glautier <spgxyz@gmail.com> 

This work is licensed for non-commercial use as follows:

Attribution-NonCommercial-ShareAlike 4.0 International.

=cut

