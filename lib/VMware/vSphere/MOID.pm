package VMware::vSphere::MOID;

use 5.012;
use warnings;

our $VERSION = '1.00';

use overload '""' => sub { return $_[0]->{moid} };

sub new {
    my ($class, $moid) = @_;
    return bless { moid => $moid }, $class;
}

1;
