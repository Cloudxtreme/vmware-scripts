#!/usr/bin/perl -w
#
# report_vm_hosts.pl
#
# Copyright (c) 2014 TheLadders.  All rights reserved.
# Matt Chesler <mchesler@theladders.com>

use strict;
use warnings;
use POSIX qw(strftime);

use constant { TRUE => 1, FALSE => 0 };

use VMware::VIRuntime;

select STDERR; $| = 1;    # make STDERR unbuffered
select STDOUT; $| = 1;    # make STDOUT unbuffered

$Util::script_version = "1.0";

my %opts = (
   'vmname' => {
     type => "=s",
     help => "Virtual Machine name",
     required => 0,
   },
   'vmname-re' => {
     type => "=s",
     help => "Virtual Machine name regular expression",
     required => 0,
   },
   'out' => {
     type => ":s",
     help => "Filename for script output",
     required => 0,
   },
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate(\&validate);

Util::connect();
my $vms = find_vms();
process_vms($vms);
Util::disconnect();
close_log();

sub find_vms {
  my $name;
  my %filter;

  if (Opts::option_is_set('vmname')) {
    $name = Opts::get_option('vmname');
    %filter = (
      'name' => $name,
    );
  }
  else {
    $name = Opts::get_option('vmname-re');
    %filter = (
      'name' => qr/$name/i,
    );
  }

  print_msg("Looking up VMs: " . $name);

  my $vm_views = Vim::find_entity_views(
    view_type => 'VirtualMachine',
    filter    => \%filter
  );

  print_msg("VM lookup complete");

  if (scalar @$vm_views > 0) {
    print_msg("Found " . scalar @$vm_views . " VM(s)");
    return $vm_views;
  }
  else {
    bailout("No virtual machines found for " . Opts::get_option('vmname'));
  }
}

sub process_vms {
  my ($vms) = @_;

  my %vmh_mapping;

  print_msg("Collecting Host information");

  foreach my $vm (@$vms) {
    my $vm_name = $vm->name;
    my $vmh = $vm->runtime->host;
    my $vmh_name = Vim::get_view(mo_ref => $vmh)->name;

    # $vmh_mapping{$vmh_name} = [] unless defined $vmh_mapping{$vmh_name};

    push(@{$vmh_mapping{$vmh_name}}, $vm_name);
    print_msg(".", TRUE);
    # print_msg($vm_name . " => " . $vmh_name);
  }

  print_msg("Done");

  foreach my $host (sort keys %vmh_mapping) {
    print_msg($host . ":");
    foreach my $guest (@{$vmh_mapping{$host}}) {
      print_msg("  " . $guest);
    }
    print_msg("");
  }
}

sub print_msg {
  my ($message, $cr) = @_;
  unless (Opts::option_is_set('quiet')) {
    if ($cr) {
      Util::trace(0, $message);
    }
    else {
      Util::trace(0, $message . "\n");
    }
  }
  print_log($message, $cr);
}

sub print_log {
  my ($message, $cr) = @_;
  if (fileno(OUTFILE)) {
    my $timestamp = strftime("%F %T", localtime());
    if ($cr) {
      print OUTFILE $message;
    }
    else {
      print OUTFILE $timestamp . " - " . $message . "\n";
    }
  }
}

sub close_log {
  if (fileno(OUTFILE)) {
    print_log("LOG ENDED");
    close(OUTFILE);
  }
}

sub bailout {
  my ($message) = @_;
  print_msg($message);
  close_log();
  exit(1);
}

sub validate {
  my $valid = TRUE;

  unless (Opts::option_is_set('vmname') || Opts::option_is_set('vmname-re')) {
    Util::trace(0, "Must provide one of 'vmname' or 'vmname-re'");
    $valid = FALSE;
  }

  if (Opts::option_is_set('vmname') && Opts::option_is_set('vmname-re')) {
    Util::trace(0, "Cannot provide both 'vmname' and 'vmname-re' options\n");
    $valid = FALSE;
  }

  if (Opts::option_is_set('out')) {
    my $filename = Opts::get_option('out');
    if ((length($filename) == 0)) {
      Util::trace(0, "\n'$filename' Not Valid:\n$@\n");
      $valid = FALSE;
    }
    else {
      open(OUTFILE, ">$filename");
      if ((length($filename) == 0) ||
          !(-e $filename && -r $filename && -T $filename)) {
        Util::trace(0, "\n'$filename' Not Valid:\n$@\n");
        $valid = FALSE;
      }
      else {
        print_log("LOG STARTED");
      }
    }
  }

  return $valid;
}

__END__

=head1 NAME

report_vm_hosts.pl - Given a VM name or regular expression, report the physical host on which the VM or VMs reside

=head1 SYNOPSIS

 report_vm_hosts.pl [VMware options] [options]

=head1 DESCRIPTION

This command will query a vCenter server to determine the physical host
location of a specified virtual host.

=head1 VMWARE OPTIONS

In addition to the command specific options, there are general
VMware Perl SDK options that can be used:

=over

=item B<config> (variable VI_CONFIG)

Location of the VI Perl configuration file

=item B<credstore> (variable VI_CREDSTORE)

Name of the credential store file defaults to
<HOME>/.vmware/credstore/vicredentials.xml on Linux and
<APPDATA>/VMware/credstore/vicredentials.xml on Windows

=item B<encoding> (variable VI_ENCODING, default 'utf8')

Encoding: utf8, cp936 (Simplified Chinese), iso-8859-1 (German), shiftjis (Japanese)

=item B<help>

Display usage information for the script

=item B<passthroughauth> (variable VI_PASSTHROUGHAUTH)

Attempt to use pass-through authentication

=item B<passthroughauthpackage> (variable VI_PASSTHROUGHAUTHPACKAGE, default 'Negotiate')

Pass-through authentication negotiation package

=item B<password> (variable VI_PASSWORD)

Password

=item B<portnumber> (variable VI_PORTNUMBER)

Port used to connect to server

=item B<protocol> (variable VI_PROTOCOL, default 'https')

Protocol used to connect to server

=item B<savesessionfile> (variable VI_SAVESESSIONFILE)

File to save session ID/cookie to utilize

=item B<server> (variable VI_SERVER, default 'localhost')

VI server to connect to. Required if url is not present

=item B<servicepath> (variable VI_SERVICEPATH, default '/sdk/webService')

Service path used to connect to server

=item B<sessionfile> (variable VI_SESSIONFILE)

File containing session ID/cookie to utilize

=item B<url> (variable VI_URL)

VI SDK URL to connect to. Required if server is not present.

=item B<username> (variable VI_USERNAME)

ESXi or vCenter Username

=item B<verbose> (variable VI_VERBOSE)

Display additional debugging information

=item B<version>

Display version information for the script

=back

=head1 OPTIONS

=over

=item B<vmname>

Required. The name of the virtual machine. It will be used to select the
virtual machine.  Cannot be used in conjunction with the B<vmname-re>
option.

=item B<vmname-re>

Required. A Perl regular expression describing the name of one or more
virtual machines.  If the regular expression matches multiple Virtual
Machines, it will select all matching hosts.  Cannot be used in conjunction
with the B<vmware> option.

=item B<out>

Optional. Filename to which output is written.  If the file option is not
suppled, output will only be displayed to the console.

=back

=head1 PREREQUISITES

The functionality provided by this command relies on the vSphere Perl SDK
for vSphere (https://developercenter.vmware.com/web/sdk/55/vsphere-perl)

=head1 EXAMPLES

Find all 'foo' Virtual Machines:

  report_vm_hosts.pl --vmname-re foo

Find a single Virtual Machine named 'bar', send output to 'filename.txt':

  report_vm_hosts.pl --vmname bar -out filename.txt

Sample Output

 $ report_vm_hosts.pl --vmname-re test-host --out foo.txt
 Looking up VMs: test-host
 VM lookup complete
 Found 4 VM(s)
 Collecting Host information
 ....Done
 esx-01:
   test-host-1
   test-host-3

 esx-02:
   test-host-2
   test-host-4

=head1 SUPPORTED PLATFORMS

This command is tested and known to work with vCenter 5.5u1 and ESXi 5.5u1
