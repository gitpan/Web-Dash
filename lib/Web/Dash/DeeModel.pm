package Web::Dash::DeeModel;
use strict;
use warnings;
use Carp;
use Future::Q;
use Scalar::Util qw(looks_like_number);
use Web::Dash::Util qw(future_dbus_call);
use Encode ();

sub new {
    my ($class, %args) = @_;
    croak "parameter bus is mandatory" if not defined $args{bus};
    croak "parameter service_name is mandatory" if not defined $args{service_name};
    croak "parameter schema is mandatory" if not defined $args{schema};
    my $self = bless {
        dbus_obj => undef,
        schema => $args{schema},
    }, $class;
    my $service_name = $args{service_name};
    $self->{dbus_obj} =
        $args{bus}->get_service($service_name)->get_object(_model_object_from_service($service_name), 'com.canonical.Dee.Model');
    return $self;
}

sub _model_object_from_service {
    my ($model_service_name) = @_;
    my $name = $model_service_name;
    $name =~ s|\.|/|g;
    return "/com/canonical/dee/model/$name";
}

sub _extract_valid_values {
    my ($row_schema, $row_data) = @_;
    my $field_num = int(@$row_schema);
    return [] if !$field_num;
    my @values = grep { @$_ == $field_num } @$row_data;
    return \@values;
}

sub _row_to_hashref {
    my ($self, $row) = @_;
    my $schema = $self->{schema};
    my %converted = ();
    foreach my $key_index (keys %$schema) {
        my $key_name = $schema->{$key_index};
        my $value = $row->[$key_index];
        if(defined $value) {
            if(looks_like_number($value)) {
                $value += 0;    ## numerify
            }else {
                $value = Encode::decode('utf8', $value);
            }    
        }
        $converted{$key_name} = $value;
    }
    return \%converted;
}

sub get {
    my ($self, $exp_seqnum) = @_;

    ## --- Get current value of the Dee Model
    ##     By calling "Clone" method on a Dee Model object, we can obtain
    ##     current value of the Dee Model object.
    
    ##     Alternatively, we can listen on "Commit" signal to keep track of
    ##     changes made on the Dee Model. That way, we can collect every value
    ##     the Model has ever had. However, here we use "Clone" method to obtain
    ##     the Model's value for ease of implementation.
    
    return future_dbus_call($self->{dbus_obj}, "Clone")->then(sub {
        my ($swarm_name, $row_schema, $row_data, $positions, $change_types, $seqnum_before_after) = @_;
        ## -- Obtain the raw data, convert it into a list of hash-refs
        ##    Dee Model's data model is similar to spreadsheets or RDB.
        ##    $row_schema is an array of strings, each of which indicates the data
        ##    type of the column. The string format is in DBus-way, I guess.
        ##    $row_data is an array of arrays, each of which represents a data row.
        ##    A data row may be empty, which I guess is some kind of placeholder from
        ##    the previous state of the Model. Otherwise, a data row has the same
        ##    number of data as the $row_schema.
        ##    $seqnum_before_after is an array with two elements. Its first element
        ##    is the previous sequence number of the Model and the second element
        ##    is the current sequence number.
        
        if(defined($exp_seqnum)) {
            my $result_seqnum = $seqnum_before_after->[1];
            if($result_seqnum != $exp_seqnum) {
                die "This seqnum is not expected.\n";
            }
        }
        return map { $self->_row_to_hashref($_) } @{_extract_valid_values($row_schema, $row_data)};
    });
}

our $VERSION = "0.041";

1;

__END__

=pod

=head1 NAME

Web::Dash::DeeModel - remote Dee Model object

=head1 VERSION

0.041

=head1 DESCRIPTION

L<Web::Dash::DeeModel> represents the remote Dee Model object on DBus.

This module is not meant for end users. Use L<Web::Dash::Lens> instead.

=head1 CLASS METHODS

=head2 $model = Web::Dash::DeeModel->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<bus> => Net::DBus bus object (mandatory)

The DBus bus to be used.

=item C<service_name> => STR (mandatory)

The DBus service name for the Dee Model.
Its DBus object name is automatically generated by the service name.

=item C<schema> => HASHREF (mandatory)

The schema of the Dee Model.

C<schema> is a hash-ref. Its key is an integer, which is a column index of
the raw Dee Model.
Its value is a string, which is the name for the column.

=back

=head1 OBJECT METHODS

=head2 $future = $model->get([$exp_seqnum])

Returns a L<Future::Q> object that represents the current values of the C<$model>.

If C<$exp_seqnum> is specified, the seqnum of obtained values will be checked.
If the current seqnum is not equal to C<$exp_seqnum>, C<$future> will be rejected.

In success, C<$future> will be fulfilled with the current values of the C<$model>.
They are a list of hash-refs transformed by the schema specified in C<new()>.

In failure, C<$future> will be rejected.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut



