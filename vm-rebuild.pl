#!/usr/bin/perl -w
#
# vm-rebuild.pl
#
# Copyright (c) 2014 TheLadders.  All rights reserved.
# Matt Chesler <mchesler@theladders.com>

use strict;
use warnings;
use POSIX qw(strftime);

use constant { TRUE => 1, FALSE => 0 };

use VMware::VIRuntime;

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
   'quiet' => {
     type => ":i",
     help => "Suppress STDOUT logging",
     required => 0,
   },
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate(\&validate);

Util::connect();
my $vms = find_vms();
process_vms($vms) if (prompt_user("Continue? "));
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
    my @vmlist;
    foreach my $vm (@$vm_views) {
      push(@vmlist, $vm->name);
    }
    print_msg(join(', ', @vmlist));
    return $vm_views;
  }
  else {
    bailout("No virtual machines found for " . $name;
  }
}

sub process_vms {
  my ($vms) = @_;

  print_msg("Rebuilding " . scalar @$vms . " VM(s)");

  foreach my $vm (@$vms) {
    my $message = "Verify that " . $vm->name . " is configured to build on next boot\n";
    $message .= "Are you sure you want to rebuild " . $vm->name? . " ";

    if (prompt_user($message)) {
      set_netboot($vm);
      reboot($vm);
      sleep(10);
      restore_boot($vm);
    }
    else {
      print_msg("Skipping rebuild of " . $vm->name);
    }
  }
}

sub prompt_user {
  my ($message) = @_;

  return TRUE if Opts::option_is_set('quiet');

  print $message;

  my $input = <STDIN>;
  $input =~ s/[nrft]//g;
  if ($input =~ /^y$|^yes$/i) {
    return TRUE;
  }
  else {
    return FALSE;
  }
}

sub set_netboot {
  my ($vm) = @_;

  print_msg("Setting netboot for " . $vm->name);

  my $vm_config_spec = VirtualMachineConfigSpec->new(
    name => $vm->name,
    extraConfig => [
      OptionValue->new(
        key => 'bios.bootDeviceClasses',
        value => 'allow:net'
      ),
    ]
  );
  $vm->ReconfigVM( spec => $vm_config_spec );
}

sub restore_boot {
  my ($vm) = @_;

  print_msg("Restoring boot order for " . $vm->name);

  my $vm_config_spec = VirtualMachineConfigSpec->new(
    name => $vm->name,
    extraConfig => [
      OptionValue->new(
        key => 'bios.bootDeviceClasses',
        value => 'allow:hd'
      ),
    ]
  );
  $vm->ReconfigVM( spec => $vm_config_spec );
}

sub reboot {
  my ($vm) = @_;

  print_msg("Rebooting " . $vm->name);

  my $mor_host = $vm->runtime->host;
  my $hostname = Vim::get_view(mo_ref => $mor_host)->name;
  eval {
    if ($vm->runtime->powerState->val eq 'poweredOn') {
      $vm->ResetVM();
      print_msg("Virtual Machine '" . $vm->name . "' on $hostname reset successfully");
    }
    else {
      $vm->PowerOnVM();
      print_msg("Virtual Machine '" . $vm->name . "' on $hostname powered on successfully");
    }
  };
  if ($@) {
    if (ref($@) eq 'SoapFault') {
      print_msg("Error in '" . $vm->name . "' under host $hostname: ");
      if (ref($@->detail) eq 'InvalidState') {
        print_msg("Host is in maintenance mode");
      }
      elsif (ref($@->detail) eq 'InvalidPowerState') {
        print_msg("The attempted operation cannot be performed in the current state" );
      }
      elsif (ref($@->detail) eq 'NotSupported') {
        print_msg("Virtual machine is marked as a template");
      }
      else {
        print_msg("VM '" . $vm->name . "' can't be reset\n" . $@ . "");
      }
    }
    else {
      print_msg("VM '" . $vm->name . "' can't be reset \n" . $@ . "");
    }
  }
}

sub print_msg {
  my ($message) = @_;
  unless (Opts::option_is_set('quiet')) {
    Util::trace(0, $message . "\n");
  }
  print_log($message);
}

sub print_log {
  my ($message) = @_;
  if (fileno(OUTFILE)) {
    my $timestamp = strftime("%F %T", localtime());
    print OUTFILE  $timestamp . " - " . $message . "\n";
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

vm-rebuild.pl - Perform OS reinstall for specified Virtual Machines

=head1 SYNOPSIS

 vm-rebuild.pl [VMware options] [options]

=head1 DESCRIPTION

This command provides an interface to temporarily adjust the boot order for
a virtual machine so it will perform a PXE boot.  It sets the boot device to
'net', instructs VMware to reset the Virtual Machine, then sets the boot
device back to 'hd'.  This requires that a PXE boot environment exists and
is configured to perform network-based installations.

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

=item B<quiet>

Optional. Suppress console output and assume an affirmative response to all
prompts.

=back

=head1 PREREQUISITES

The functionality provided by this command relies on the vSphere Perl SDK
for vSphere (https://developercenter.vmware.com/web/sdk/55/vsphere-perl)

=head1 EXAMPLES

Rebuild all 'foo' Virtual Machines:

  vm-rebuild.pl --vmname-re foo

Rebuild a single Virtual Machine named 'bar', send output to 'filename.txt':

  vm-rebuild.pl --vmname bar -out filename.txt

Sample Output

 $ vm-rebuild.pl --vmname test-host-1 --out foo.txt
 Looking up VMs: test-host-1
 VM lookup complete
 Rebuilding 1 VM(s)
 Verify that test-host-1 is configured to build on next boot
 Are you sure you want to rebuild test-host-1? y
 Setting netboot for test-host-1
 Rebooting test-host-1
 Virtual Machine 'test-host-1' on esxi-1.example.com reset successfully
 Restoring boot order for test-host-1

=head1 SUPPORTED PLATFORMS

This command is tested and known to work with vCenter 5.5u1 and ESXi 5.5u1
