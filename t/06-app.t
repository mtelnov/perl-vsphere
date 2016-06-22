use strict;
use Test::More;

use VMware::vSphere::App;

open my $fh_out, '>', \my $stdout or diag("Can't open in-memory handler");
open my $fh_err, '>', \my $stderr or diag("Can't open in-memory handler");
my $app = new_ok('VMware::vSphere::App' => [
    stderr => $fh_err,
    stdout => $fh_out,
]);
my $test = '';

sub new_test {
    $test = shift;
    $stderr = '';
    $stdout = '';
    $fh_err->seek(0, 0);
    $fh_out->seek(0, 0);
}

new_test('show_usage');
ok(!defined($app->show_usage()), $test);
like($stderr, qr{
        ^vsphere.*
        Usage:.*
        \nget_moid\n.*
        VMware::vSphere::Simple\n$
    }sx, 'show_usage (stderr)');
is($stdout, '', "$test (stdout)");
my $show_usage = $stderr;

new_test('help()');
ok(!defined($app->help()), $test);
is($stderr, $show_usage, "$test (stderr)");
is($stdout, '', "$test (stdout)");

new_test('help($method)');
ok($app->help('list'), $test);
is($stderr, '', "$test (stderr)");
like($stdout, qr{Returns a list with names}, "$test (stdout)");

new_test('help($not_existent_method)');
ok(!defined($app->help('NOtExisT')), $test);
is($stderr, "Error: Method 'NOtExisT' not found.\n".$show_usage, "$test (stderr)");
is($stdout, '', "$test (stdout)");

new_test('completion');
ok($app->completion(1, 'test'), $test);
is($stderr, '', "$test (stderr)");
like($stdout, qr{help.* list }, "$test (stdout)");

done_testing();
