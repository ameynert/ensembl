#
# Ensembl module for Transcript
#
# Copyright (c) 1999-2004 Ensembl
#
# You may distribute this module under the same terms as perl itself
#

=head1 NAME

Transcript - gene transcript object

=head1 SYNOPSIS

=head1 DESCRIPTION

Contains details of coordinates of all exons that make
up a gene transcript.

Creation:

     my $tran = new Bio::EnsEMBL::Transcript();
     my $tran = new Bio::EnsEMBL::Transcript(-EXONS => \@exons);

Manipulation:

     # Returns an array of Exon objects
     my @exons = @{$tran->get_all_Exons};
     # Returns the peptide translation of the exons as a Bio::Seq
     my $pep   = $tran->translate();


=head1 CONTACT

Email questions to the ensembl developer mailing list <ensembl-dev@ebi.ac.uk>

=head1 METHODS

=cut

package Bio::EnsEMBL::Transcript;
use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Feature;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Intron;
use Bio::EnsEMBL::Translation;
use Bio::Tools::CodonTable;
use Bio::EnsEMBL::TranscriptMapper;

use Bio::EnsEMBL::Utils::Argument qw( rearrange );
use Bio::EnsEMBL::Utils::Exception qw( deprecate warning throw );


@ISA = qw(Bio::EnsEMBL::Feature);

sub new {
  my($class) = shift;

  if( ref $class ) { 
      $class = ref $class;
  }

  my $self = $class->SUPER::new(@_);

  my ( $exons, $stable_id, $version, $external_name, $external_db,
       $external_status, $display_xref );

  #catch for old style constructor calling:
  if((@_ > 0) && ref($_[0])) {
    $exons = [@_];
    deprecate("Transcript constructor should use named arguments.\n" .
              'Use Bio::EnsEMBL::Transcript->new(-EXONS => \@exons);' .
              "\ninstead of Bio::EnsEMBL::Transcript->new(\@exons);");
  }
  else {
    ( $exons, $stable_id, $version, $external_name, $external_db,
      $external_status, $display_xref ) = 
        rearrange( [ "EXONS", 'STABLE_ID', 'VERSION', 'EXTERNAL_NAME', 
                     'EXTERNAL_DB', 'EXTERNAL_STATUS', 'DISPLAY_XREF' ], @_ );
  }

  if( $exons ) {
    $self->{'_trans_exon_array'} = $exons;
    $self->recalculate_coordinates();
  }

  $self->stable_id( $stable_id );
  $self->version( $version );
  $self->external_name( $external_name ) if( defined $external_name );
  $self->external_db( $external_db ) if( defined $external_db );
  $self->external_status( $external_status ) if( defined $external_status );
  $self->display_xref( $display_xref ) if( defined $display_xref );

  return $self;
}


=head2 get_all_DBLinks

  Arg [1]    : none
  Example    : @dblinks = @{$transcript->get_all_DBLinks()};
  Description: Retrieves _all_ related DBEntries for this transcript.  
               This includes all DBEntries that are associated with the
               corresponding translation.

               If you only want to retrieve the DBEntries associated with the
               transcript then you should use the get_all_DBEntries call 
               instead.
  Returntype : list reference to Bio::EnsEMBL::DBEntry objects
  Exceptions : none
  Caller     : general

=cut

sub get_all_DBLinks {
  my $self = shift;

  my @links;

  push @links, @{$self->get_all_DBEntries};

  my $transl = $self->translation();
  push @links, @{$transl->get_all_DBEntries} if($transl);

  return \@links;
}


=head2 get_all_DBEntries

  Arg [1]    : none
  Example    : @dbentries = @{$gene->get_all_DBEntries()};
  Description: Retrieves DBEntries (xrefs) for this transcript.  
               This does _not_ include the corresponding translations 
               DBEntries (see get_all_DBLinks).

               This method will attempt to lazy-load DBEntries from a
               database if an adaptor is available and no DBEntries are present
               on the transcript (i.e. they have not already been added or 
               loaded).
  Returntype : list reference to Bio::EnsEMBL::DBEntry objects
  Exceptions : none
  Caller     : get_all_DBLinks, TranscriptAdaptor::store

=cut

sub get_all_DBEntries {
  my $self = shift;

  #if not cached, retrieve all of the xrefs for this gene
  if(!defined $self->{'dbentries'} && $self->adaptor()) {
    $self->{'dbentries'} = 
      $self->adaptor->db->get_DBEntryAdaptor->fetch_all_by_Transcript($self);
  }

  $self->{'dbentries'} ||= [];

  return $self->{'dbentries'};
}


=head2 add_DBEntry

  Arg [1]    : Bio::EnsEMBL::DBEntry $dbe
               The dbEntry to be added
  Example    : @dbentries = @{$gene->get_all_DBEntries()};
  Description: Associates a DBEntry with this gene. Note that adding DBEntries
               will prevent future lazy-loading of DBEntries for this gene
               (see get_all_DBEntries).
  Returntype : none
  Exceptions : thrown on incorrect argument type
  Caller     : general

=cut

sub add_DBEntry {
  my $self = shift;
  my $dbe = shift;

  unless($dbe && ref($dbe) && $dbe->isa('Bio::EnsEMBL::DBEntry')) {
    throw('Expected DBEntry argument');
  }

  $self->{'dbentries'} ||= [];
  push @{$self->{'dbentries'}}, $dbe;
}



=head2 external_db

 Title   : external_db
 Usage   : $ext_db = $obj->external_db();
 Function: external_name if available
 Returns : the external db link for this transcript
 Args    : new external db (optional)

=cut

sub external_db {
  my ( $self, $ext_dbname ) = @_;

  if(defined $ext_dbname) { 
    return ( $self->{'external_db'} = $ext_dbname );
  } 

  if( exists $self->{'external_db'} ) {
    return $self->{'external_db'};
  }

  my $display_xref = $self->display_xref();

  if( defined $display_xref ) {
    return $display_xref->dbname()
  } else {
    return undef;
  }
}



=head2 external_status

 Title   : external_status
 Usage   : $ext_db = $obj->external_status();
 Function: external_name if available
 Returns : the external db link for this transcript
 Args    : new external db (optional)

=cut

sub external_status { 
  my ( $self, $ext_status ) = @_;

  if(defined $ext_status) {
    return ( $self->{'external_status'} = $ext_status );
  }

  if( exists $self->{'external_status'} ) {
    return $self->{'external_status'};
  }

  my $display_xref = $self->display_xref();

  if( defined $display_xref ) {
    return $display_xref->status()
  } else {
    return undef;
  }
}



=head2 external_name

 Title   : external_name
 Usage   : $ext_name = $obj->external_name();
 Function: external_name if available
 Example : 
 Returns : the external name of this transcript
 Args    : new external name (optional)

=cut


sub external_name {
  my ($self, $ext_name) = @_;

  if(defined $ext_name) { 
    return ( $self->{'external_name'} = $ext_name );
  } 

  if( exists $self->{'external_name'} ) {
    return $self->{'external_name'};
  }

  my $display_xref = $self->display_xref();

  if( defined $display_xref ) {
    return $display_xref->display_id()
  } else {
    return undef;
  }
}


=head2 is_known

  Args       : none
  Example    : none
  Description: returns true if this transcript has a display_xref
  Returntype : 0,1
  Exceptions : none
  Caller     : general

=cut

sub is_known {
  my $self = shift;
  return ($self->{'display_xref'}) ? 1 : 0;
}


sub type {
  my $self = shift;

  $self->{'type'} = shift if( @_ );
  return $self->{'type'};
}


=head2 display_xref

  Arg [1]    : Bio::EnsEMBL::DBEntry $display_xref
  Example    : $transcript->display_xref(Bio::EnsEMBL::DBEntry->new(...));
  Description: getter setter for display_xref for this transcript
  Returntype : Bio::EnsEMBL::DBEntry
  Exceptions : none
  Caller     : general

=cut

sub display_xref {
  my $self = shift;
  $self->{'display_xref'} = shift if(@_);
  return $self->{'display_xref'};
}


=head2 translation

 Title   : translation
 Usage   : $obj->translation($newval)
 Function: 
 Returns : value of translation
 Args    : newvalue (optional)


=cut

sub translation {
  my $self = shift;
  if( @_ ) {
    my $value = shift;
    if( defined($value) &&
        (!ref($value) || !$value->isa('Bio::EnsEMBL::Translation'))) {
      throw("Bio::EnsEMBL::Translation argument expected.");
    }
    $self->{'translation'} = $value;
  } elsif( !exists($self->{'translation'}) and defined($self->adaptor())) {
    $self->{'translation'} =
      $self->adaptor()->db()->get_TranslationAdaptor()->
        fetch_by_Transcript( $self );
  }
  return $self->{'translation'};
}



=head2 spliced_seq

  Args       : none
  Example    : none
  Description: retrieves all Exon sequences and concats them together. No phase padding magic is 
               done, even if phases dont align.
  Returntype : txt
  Exceptions : none
  Caller     : general

=cut

sub spliced_seq {
  my ( $self ) = @_;

  my $seq_string = "";
  for my $ex ( @{$self->get_all_Exons()} ) {
    my $seq = $ex->seq();

    if(!$seq) {
      warning("Could not obtain seq for exon.  Transcript sequence may not " .
              "be correct.");
      $seq_string .= 'N' x $ex->length();
    } else {
      $seq_string .= $seq->seq();
    }
  }

  return $seq_string;
}


=head2 edited_seq

  Args       : none
  Example    : none
  Description: Retrieves the spliced_seq and applies all _rna_edit attributes
               to it. It will adjust cdna_coding_start and cdna_coding_end.
               These will be used by translateable_seq to extract the sequence that is 
               to translate.

               The format of _rna_edit attribute value is "start end alt_sequence"
               start and end are zero based in_between coords to describe the location
               in the cdna of the alt_sequence. Inserts have the same start and end.
               Deletes have no alt_sequence.

               WARNING! This function has to modify the start and end position of the 
               translation!
  Returntype : txt
  Exceptions : none
  Caller     : general

=cut

sub edited_seq {
  my ( $self ) = @_;

  my $attribs = $self->get_all_Attributes( "_rna_edit" );
  my $seq = $self->spliced_seq();

  my $cdna_coding_start = $self->cdna_coding_start( undef );
  my $cdna_coding_end = $self->cdna_coding_end( undef );
  
  my $translation;
  if( $cdna_coding_start && $cdna_coding_end ) {
    $translation = 1;
  } else {
    $translation = 0;
  }

  my @edits;

  for my $attrib ( @$attribs ) {
    my ( $start, $end, $alt_seq ) = split( " ", $attrib->value());
    # length diff is the adjustment to do on cdna_coding_start/end
    my $length_diff = ( CORE::length( $alt_seq ) - ( $end - $start));
    push( @edits, [ $start, $end, $alt_seq, $length_diff ] );
  }

  @edits = sort { $b->[0] <=> $a->[0] } @edits;

  for my $edit ( @edits ) {
    # applying the edit
    substr( $seq, $edit->[0], $edit->[1]-$edit->[0] ) = $edit->[2];
    
    my $diff = $edit->[3];
    if( $diff != 0 ) {
      # possibly adjust cdna start/end
      if( $edit->[0]+1 <= $cdna_coding_end ) {
        $cdna_coding_end += $diff;
      }
      if( $edit->[0]+1 < $cdna_coding_start ) {
        $cdna_coding_start += $diff;
      }
    }
  }

  if( $translation ) {
    $self->cdna_coding_start( $cdna_coding_start );
    $self->cdna_coding_end( $cdna_coding_end );
  }

  return $seq;
}




=head2 translateable_seq

  Args       : none
  Example    : print $transcript->translateable_seq(), "\n";
  Description: Returns a sequence string which is the the translateable part 
               of the transcripts sequence.  This is formed by splicing all
               Exon sequences together and apply all defined RNA edits. Then the
               coding part of the sequence is extracted and returned.

               The code will not support monkey exons any more. If you want to have
               non phase matching exons, defined appropriate _rna_edit attributes!
  Returntype : txt
  Exceptions : none
  Caller     : general

=cut

sub translateable_seq {
  my ( $self ) = @_;

  # IMPORTANT: first extract the sequence, then the cdna start/end
  # because editing may modify this positions.
  my $mrna = $self->edited_seq();
  my $start = $self->cdna_coding_start();
  my $end = $self->cdna_coding_end();
  
  if( ! $start || ! $end ) {
    return "";
  }

  my $seq = substr( $mrna, $start-1, $end-$start+1 );

  return $seq;
}



=head2 cdna_coding_start

  Arg [1]    : (optional) $value
  Example    : $relative_coding_start = $transcript->cdna_coding_start;
  Description: Retrieves the position of the coding start of this transcript
               in cdna coordinates (relative to the start of the 5prime end of
               the transcript, excluding introns, including utrs).
  Returntype : int
  Exceptions : none
  Caller     : five_prime_utr, get_all_snps, general

=cut

sub cdna_coding_start {
  my $self = shift;

  if( @_ ) {
    $self->{'cdna_coding_start'} = shift;
  } 

  if(!defined $self->{'cdna_coding_start'} && defined $self->translation){
    #
    #calculate the coding start relative from the start of the
    #translation (in cdna coords)
    #
    my $start = 0;

    my @exons = @{$self->get_all_Exons};
    my $exon;

    while($exon = shift @exons) {
      if($exon == $self->translation->start_Exon) {
        #add the utr portion of the start exon
        $start += $self->translation->start;
        last;
      } else {
        #add the entire length of this non-coding exon
        $start += $exon->length;
      }
    }
    $self->{'cdna_coding_start'} = $start;
  }

  return $self->{'cdna_coding_start'};
}



=head2 cdna_coding_end

  Arg [1]    : (optional) $value
  Example    : $cdna_coding_end = $transcript->cdna_coding_end;
  Description: Retrieves the end of the coding region of this transcript in
               cdna coordinates (relative to the five prime end of the
               transcript, excluding introns, including utrs).
               Note 
  Returntype : none
  Exceptions : none
  Caller     : general

=cut

sub cdna_coding_end {
  my $self = shift;

  if( @_ ) {
    $self->{'cdna_coding_end'} = shift;
  } 
  
  if(!defined $self->{'cdna_coding_end'} && defined $self->translation) {
    my @exons = @{$self->get_all_Exons};

    my $end = 0;
    while(my $exon = shift @exons) {
      if($exon == $self->translation->end_Exon) {
	#add the coding portion of the final coding exon
	$end += $self->translation->end;
	last;
      } else {
	#add the entire exon
	$end += $exon->length;
      }
    }
    $self->{'cdna_coding_end'} = $end;
  }

  return $self->{'cdna_coding_end'};
}



=head2 coding_region_start

  Arg [1]    : (optional) $value
  Example    : $coding_region_start = $transcript->coding_region_start
  Description: Retrieves the start of the coding region of this transcript
               in genomic coordinates (i.e. in either slice or contig coords).
               By convention, the coding_region_start is always lower than
               the value returned by the coding_end method.
               The value returned by this function is NOT the biological
               coding start since on the reverse strand the biological coding
               start would be the higher genomic value.
  Returntype : int
  Exceptions : none
  Caller     : general

=cut

sub coding_region_start {
  my ($self, $value) = @_;

  if( defined $value ) {
    $self->{'coding_region_start'} = $value;
  } elsif(!defined $self->{'coding_region_start'} && 
	  defined $self->translation) {
    #calculate the coding start from the translation
    my $start;
    my $strand = $self->translation()->start_Exon->strand();
    if( $strand == 1 ) {
      $start = $self->translation()->start_Exon->start();
      $start += ( $self->translation()->start() - 1 );
    } else {
      $start = $self->translation()->end_Exon->end();
      $start -= ( $self->translation()->end() - 1 );
    }
    $self->{'coding_region_start'} = $start;
  }

  return $self->{'coding_region_start'};
}



=head2 coding_region_end

  Arg [1]    : (optional) $value
  Example    : $coding_region_end = $transcript->coding_region_end
  Description: Retrieves the start of the coding region of this transcript
               in genomic coordinates (i.e. in either slice or contig coords).
               By convention, the coding_region_end is always higher than the 
               value returned by the coding_region_start method.  
               The value returned by this function is NOT the biological 
               coding start since on the reverse strand the biological coding 
               end would be the lower genomic value.
  Returntype : int
  Exceptions : none
  Caller     : general

=cut

sub coding_region_end {
  my ($self, $value ) = @_;

  my $strand;
  my $end;

  if( defined $value ) {
    $self->{'coding_region_end'} = $value;
  } elsif( ! defined $self->{'coding_region_end'} 
	   && defined $self->translation() ) {
    $strand = $self->translation()->start_Exon->strand();
    if( $strand == 1 ) {
      $end = $self->translation()->end_Exon->start();
      $end += ( $self->translation()->end() - 1 );
    } else {
      $end = $self->translation()->start_Exon->end();
      $end -= ( $self->translation()->start() - 1 );
    }
    $self->{'coding_region_end'} = $end;
  }

  return $self->{'coding_region_end'};
}


=head2 get_all_Attributes

  Arg [1]    : optional string $attrib_code
               The code of the attribute type to retrieve values for.
  Example    : ($rna_edits) = @{$transcript->get_all_Attributes('_rna_edit')};
               @transcript_attributes    = @{$transcript->get_all_Attributes()};
  Description: Gets a list of Attributes of this transcript.
               Optionally just get Attrubutes for given code.
  Returntype : listref Bio::EnsEMBL::Attribute
  Exceptions : warning if transcript does not have attached adaptor and 
               attempts lazy load.
  Caller     : general

=cut

sub get_all_Attributes {
  my $self = shift;
  my $attrib_code = shift;

  if( ! exists $self->{'attributes' } ) {
    if(!$self->adaptor() ) {
#      warning('Cannot get attributes without an adaptor.');
      return [];
    }

    my $attribute_adaptor = $self->adaptor->db->get_AttributeAdaptor();
    $self->{'attributes'} = $attribute_adaptor->fetch_all_by_Transcript( $self );
  }

  if( defined $attrib_code ) {
    my @results = grep { uc($_->code()) eq uc($attrib_code) }  
    @{$self->{'attributes'}};
    return \@results;
  } else {
    return $self->{'attributes'};
  }
}


=head2 add_Attributes

  Arg [1...] : Bio::EnsEMBL::Attribute $attribute
               You can have more Attributes as arguments, all will be added.
  Example    : $transcript->add_Attributes($rna_edit_attribute);
  Description: Adds an Attribute to the Transcript. Usefull to do _rna_edits.
               If you add an attribute before you retrieve any from database, lazy load
               will be disabled.
  Returntype : none
  Exceptions : 
  Caller     : general

=cut

sub add_Attributes {
  my $self = shift;
  my @attribs = @_;

  if( ! exists $self->{'attributes'} ) {
    $self->{'attributes'} = [];
  }

  for my $attrib ( @attribs ) {
    if( ! $attrib->isa( "Bio::EnsEMBL::Attribute" )) {
      throw( "Argument to add_Attribute has to be an Bio::EnsEMBL::Attribute" );
    }
    push( @{$self->{'attributes'}}, $attrib );
  }
}


=head2 add_Exon

 Title   : add_Exon
 Usage   : $trans->add_Exon($exon)
 Returns : Nothing
 Args    :

=cut

sub add_Exon{
  my ($self,$exon) = @_;

  #yup - we are going to be picky here...
  unless(defined $exon && ref $exon && $exon->isa("Bio::EnsEMBL::Exon") ) {
    throw("[$exon] is not a Bio::EnsEMBL::Exon!");
  }

  $self->{'_trans_exon_array'} ||= [];

  my $was_added = 0;

  my $ea = $self->{'_trans_exon_array'};
  if( @$ea ) {
    if( $exon->strand() == 1 ) {
      if( $exon->start() > $ea->[$#$ea]->end() ) {
        push(@{$self->{'_trans_exon_array'}},$exon);
        $was_added = 1;
      } else {
        # insert it at correct place
        for( my $i=0; $i <= $#$ea; $i++ ) {
          if( $exon->end() < $ea->[$i]->start() ) {
            splice( @$ea, $i, 0, $exon );
            $was_added = 1;
            last;
          }
        }
      }
    } else {
      if( $exon->end() < $ea->[$#$ea]->start() ) {
        push(@{$self->{'_trans_exon_array'}},$exon);
        $was_added = 1;
      } else {
        # insert it at correct place
        for( my $i=0; $i <= $#$ea; $i++ ) {
          if( $exon->start() > $ea->[$i]->end() ) {
            splice( @$ea, $i, 0, $exon );
            $was_added = 1;
            last;
          }
        }
      }
    }
  } else {
    push( @$ea, $exon );
    $was_added = 1;
  }

  # sanity check:
  if(!$was_added) {
    # exon was not added because it has same end coord as start
    # of another exon
    my $all_str = '';
    foreach my $e (@$ea) {
      $all_str .= '  '.$e->start .'-'.$e->end.' ('.$e->strand.') ' .
        ($e->stable_id || '') . "\n";
    }
    my $cur_str = '  '.$exon->start.'-'.$exon->end. ' ('.$exon->strand.') '.
      ($exon->stable_id || '')."\n";
    throw("Exon overlaps with other exon in same transcript.\n" .
          "Transcript Exons:\n$all_str\n" .
          "This Exon:\n$cur_str");
    throw("Exon overlaps with other exon in same transcript.");
  }

  # recalculate start, end, slice, strand
  $self->recalculate_coordinates();
}



=head2 get_all_Exons

  Arg [1]    : none
  Example    : my @exons = @{$transcript->get_all_Exons()};
  Description: Returns an listref of the exons in this transcipr in order.
               i.e. the first exon in the listref is the 5prime most exon in 
               the transcript.
  Returntype : a list reference to Bio::EnsEMBL::Exon objects
  Exceptions : none
  Caller     : general

=cut

sub get_all_Exons {
   my ($self) = @_;
   if( ! defined $self->{'_trans_exon_array'} && defined $self->adaptor() ) {
     $self->{'_trans_exon_array'} = $self->adaptor()->db()->
       get_ExonAdaptor()->fetch_all_by_Transcript( $self );
   }
   return $self->{'_trans_exon_array'};
}

=head2 get_all_Introns

  Arg [1]    : none
  Example    : my @introns = @{$transcript->get_all_Introns()};
  Description: Returns an listref of the introns in this transcipr in order.
               i.e. the first intron in the listref is the 5prime most exon in 
               the transcript.
  Returntype : a list reference to Bio::EnsEMBL::Intron objects
  Exceptions : none
  Caller     : general

=cut

sub get_all_Introns {
   my ($self) = @_;
   if( ! defined $self->{'_trans_exon_array'} && defined $self->adaptor() ) {
     $self->{'_trans_exon_array'} = $self->adaptor()->db()->
       get_ExonAdaptor()->fetch_all_by_Transcript( $self );
   }

   my @introns=();
   my @exons = @{$self->{'_trans_exon_array'}};
   for(my $i=0; $i < scalar(@exons)-1; $i++){
     my $intron = new Bio::EnsEMBL::Intron($exons[$i],$exons[$i+1]);
     push(@introns, $intron)
   }
   return \@introns;
}



=head2 length


    my $t_length = $transcript->length

Returns the sum of the length of all the exons in
the transcript.

=cut

sub length {
    my( $self ) = @_;
    
    my $length = 0;
    foreach my $ex (@{$self->get_all_Exons}) {
        $length += $ex->length;
    }
    return $length;
}


=head2 get_all_peptide_variations

  Arg [1]    : (optional) $snps listref of coding snps in cdna coordinates
  Example    : $pep_hash = $trans->get_all_peptide_variations;
  Description: Takes an optional list of coding snps on this transcript in 
               which are in cdna coordinates and returns a hash with peptide 
               coordinate keys and listrefs of alternative amino acids as 
               values.  If no argument is provided all of the coding snps on 
               this transcript are used by default. Note that the peptide 
               encoded by the reference sequence is also present in the results
               and that duplicate peptides (e.g. resulting from synonomous 
               mutations) are discarded.  It is possible to have greated than
               two peptides variations at a given location given
               adjacent or overlapping snps. Insertion/deletion variations
               are ignored by this method. 
               Example of a data structure that could be returned:
               {  1  => ['I', 'M'], 
                 10  => ['I', 'T'], 
                 37  => ['N', 'D'], 
                 56  => ['G', 'E'], 
                 118 => ['R', 'K'], 
                 159 => ['D', 'E'], 
                 167 => ['Q', 'R'], 
                 173 => ['H', 'Q'] } 
  Returntype : hashref
  Exceptions : none
  Caller     : general

=cut

sub get_all_peptide_variations {
  my $self = shift;
  my $snps = shift;

  my $codon_table = Bio::Tools::CodonTable->new;
  my $codon_length = 3;
  my $cdna = $self->spliced_seq;

  unless(defined $snps) {
    $snps = $self->get_all_cdna_SNPs->{'coding'};
  }

  my $variant_alleles;
  my $translation_start = $self->cdna_coding_start;
  foreach my $snp (@$snps) {
    #skip variations not on a single base
    next if ($snp->start != $snp->end);

    my $start = $snp->start;
    my $strand = $snp->strand;    

    #calculate offset of the nucleotide from codon start (0|1|2)
    my $codon_pos = ($start - $translation_start) % $codon_length;

    #calculate the peptide coordinate of the snp
    my $peptide = ($start - $translation_start + 
		   ($codon_length - $codon_pos)) / $codon_length;

    #retrieve the codon
    my $codon = substr($cdna, $start - $codon_pos-1, $codon_length);

    #store each alternative allele by its location in the peptide
    my @alleles = split(/\/|\|/, lc($snp->alleles));
    foreach my $allele (@alleles) {
      next if $allele eq '-';       #skip deletions
      next if CORE::length($allele) != 1; #skip insertions

      #get_all_cdna_SNPs always gives strand of 1 now
      #if($strand == -1) {
      #  #complement the allele if the snp is on the reverse strand
      #  $allele =~ 
      #  tr/acgtrymkswhbvdnxACGTRYMKSWHBVDNX/tgcayrkmswdvbhnxTGCAYRKMSWDVBHNX/;
      #}

      #create a data structure of variant alleles sorted by both their
      #peptide position and their position within the peptides codon
      $variant_alleles ||= {};
      if(exists $variant_alleles->{$peptide}) {
        my $alleles_arr = $variant_alleles->{$peptide}->[1];
        push @{$alleles_arr->[$codon_pos]}, $allele;
      } else {
        #create a list of 3 lists (one list for each codon position)
        my $alleles_arr = [[],[],[]];
        push @{$alleles_arr->[$codon_pos]}, $allele;
        $variant_alleles->{$peptide} = [$codon, $alleles_arr];
      }
    }
  }

  my %out;
  #now generate all possible codons for each peptide and translate them
  foreach my $peptide (keys %$variant_alleles) {
    my ($codon, $alleles) = @{$variant_alleles->{$peptide}};

    #need to push original nucleotides onto each position
    #so that all possible combinations can be generated
    push @{$alleles->[0]}, substr($codon,0,1);
    push @{$alleles->[1]}, substr($codon,1,1);
    push @{$alleles->[2]}, substr($codon,2,1);

    my %alt_amino_acids;
    foreach my $a1 (@{$alleles->[0]}) {
      substr($codon, 0, 1) = $a1;
      foreach my $a2 (@{$alleles->[1]}) {
        substr($codon, 1, 1) = $a2;
        foreach my $a3 (@{$alleles->[2]}) {
          substr($codon, 2, 1) = $a3;
          my $aa = $codon_table->translate($codon);
          #print "$codon translation is $aa\n";
          $alt_amino_acids{$aa} = 1;
        }
      }
    }

    my @aas = keys %alt_amino_acids;
    $out{$peptide} = \@aas;
  }

  return \%out;
}


=head2 get_all_SNPs

  Arg [1]    : (optional) int $flanking
               The number of basepairs of transcript flanking sequence to 
               retrieve snps from (default 0) 
  Example    : $snp_hashref = $transcript->get_all_SNPs;
  Description: Retrieves all snps found within the region of this transcript. 
               The snps are returned in a hash with keys corresponding
               to the region the snp was found in.  Possible keys are:
               'three prime UTR', 'five prime UTR', 'coding', 'intronic',
               'three prime flanking', 'five prime flanking'
               If no flanking argument is provided no flanking snps will be
               obtained.
               The listrefs which are the values of the returned hash
               contain snps in coordinates of the transcript region 
               (i.e. first base = first base of the first exon on the
               postive strand - flanking bases + 1) 
  Returntype : hasref with string keys and listrefs of Bio::EnsEMBL::SNPs for 
               values
  Exceptions : none
  Caller     : general

=cut

sub get_all_SNPs {
  my $self = shift;
  my $flanking = shift;

  my %snp_hash;
  my $sa = $self->adaptor->db->get_SliceAdaptor;

  #retrieve a slice in the region of the transcript
  my $slice = $sa->fetch_by_transcript_id($self->dbID, $flanking );

  #copy this transcript, so we can work in coord system we are interested in
  my $transcript = $self->transfer( $slice );

  #get all of the snps in the transcript region
  my $snps = $slice->get_all_SNPs;

  my $trans_start  = $flanking + 1;
  my $trans_end    = $slice->length - $flanking;
  my $trans_strand = $transcript->get_all_Exons->[0]->strand;

  #classify each snp
  foreach my $snp (@$snps) {
    my $key;

    if(($trans_strand == 1 && $snp->end < $trans_start) ||
       ($trans_strand == -1 && $snp->start > $trans_end)) {
      #this snp is upstream from the transcript
      $key = 'five prime flanking';
    }

    elsif(($trans_strand == 1 && $snp->start > $trans_end) ||
	  ($trans_strand == -1 && $snp->start < $trans_start)) {
      #this snp is downstream from the transcript
      $key = 'three prime flanking';
    }

    else {
      #snp is inside transcript region check if it overlaps an exon
      foreach my $e (@{$transcript->get_all_Exons}) {
        if($snp->end >= $e->start && $snp->start <= $e->end) {
          #this snp is in an exon

          if(($trans_strand == 1 && 
              $snp->end < $transcript->coding_region_start) ||
             ($trans_strand == -1 && 
              $snp->start > $transcript->coding_region_end)) {
            #this snp is in the 5' UTR
            $key = 'five prime UTR';
          }

          elsif(($trans_strand == 1 && 
                 $snp->start > $transcript->coding_region_end)||
                ($trans_strand == -1 && 
                 $snp->end < $transcript->coding_region_start)) {
            #this snp is in the 3' UTR
            $key = 'three prime UTR';
          }

          else {
            #snp is coding
            $key = 'coding';
          }
          last;
        }
      }
      unless($key) {
        #snp was not in an exon and is therefore intronic
        $key = 'intronic';
      }
    }

    unless($key) {
      #warning('SNP could not be mapped. In/Dels not supported yet...');
      next;
    }

    if(exists $snp_hash{$key}) {
      push @{$snp_hash{$key}}, $snp;
    } else {
      $snp_hash{$key} = [$snp];
    }
  }

  return \%snp_hash;
}



=head2 get_all_cdna_SNPs

  Arg [1]    : none 
  Example    : $cdna_snp_hasref = $transcript->get_all_cdna_SNPs;
  Description: Retrieves all snps found within exons of this transcript. 
               The snps are returned in a hash with three keys corresponding
               to the region the snp was found in.  Valid keys are:
               'three prime UTR', 'five prime UTR', 'coding'
               The listrefs which are the values of the returned hash
               contain snps in CDNA coordinates.
  Returntype : hasref with string keys and listrefs of Bio::EnsEMBL::SNPs for 
               values
  Exceptions : none
  Caller     : general

=cut

sub get_all_cdna_SNPs {
  my ($self) = shift;

  #retrieve all of the snps from this transcript
  my $all_snps = $self->get_all_SNPs;
  my %snp_hash;

  my @cdna_types = ('three prime UTR', 'five prime UTR','coding');

  my $sa = $self->adaptor->db->get_SliceAdaptor;
  my $slice = $sa->fetch_by_transcript_id($self->dbID);

  #copy this transcript, so we can work in coord system we are interested in
  my $transcript = $self->transfer($slice);

  foreach my $type (@cdna_types) {
    $snp_hash{$type} = [];
    foreach my $snp (@{$all_snps->{$type}}) {
      my @coords = $transcript->genomic2cdna($snp->start, $snp->end,
                                             $snp->strand);

      #skip snps that don't map cleanly (possibly an indel...)
      if(scalar(@coords) != 1) {
        #warning("snp of type $type does not map cleanly\n");
        next;
      }

      my ($coord) = @coords;

      unless($coord->isa('Bio::EnsEMBL::Mapper::Coordinate')) {
        #warning("snp of type $type maps to gap\n");
        next;
      }

      my $alleles = $snp->{'alleles'};
      my $ambicode = $snp->{'_ambiguity_code'};

      #we arbitrarily put the SNP on the +ve strand because it is easier to
      #work with in the webcode.
      if($coord->strand == -1) {
        $alleles =~
         tr/acgthvmrdbkynwsACGTDBKYHVMRNWS\//tgcadbkyhvmrnwsTGCAHVMRDBKYNWS\//;
        $ambicode =~
         tr/acgthvmrdbkynwsACGTDBKYHVMRNWS\//tgcadbkyhvmrnwsTGCAHVMRDBKYNWS\//;
      }

      #copy the snp and convert to cdna coords...
      my $new_snp;
      %$new_snp = %$snp;
      bless $new_snp, ref $snp;
      $new_snp->start($coord->start);
      $new_snp->end($coord->end);
      $new_snp->strand(1);
      $new_snp->{'alleles'} = $alleles;
      $new_snp->{'_ambiguity_code'} = $ambicode;
      push @{$snp_hash{$type}}, $new_snp;
    }
  }

  return \%snp_hash;
}


=head2 flush_Exons

 Title   : flush_Exons
 Usage   : Removes all Exons from the array.
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub flush_Exons{
   my ($self,@args) = @_;
   $self->{'transcript_mapper'} = undef;
   $self->{'coding_region_start'} = undef;
   $self->{'coding_region_end'} = undef;
   $self->{'cdna_coding_start'} = undef;
   $self->{'cdna_coding_end'} = undef;
   $self->{'start'} = undef;
   $self->{'end'} = undef;
   $self->{'strand'} = undef;

   $self->{'_trans_exon_array'} = [];
}



=head2 five_prime_utr and three_prime_utr

    my $five_prime  = $transcrpt->five_prime_utr
        or warn "No five prime UTR";
    my $three_prime = $transcrpt->three_prime_utr
        or warn "No three prime UTR";

These methods return a B<Bio::Seq> object
containing the sequence of the five prime or
three prime UTR, or undef if there isn't a UTR.

Both method throw an exception if there isn't a
translation attached to the transcript object.

=cut

sub five_prime_utr {
  my $self = shift;

  my $seq = substr($self->spliced_seq, 0, $self->cdna_coding_start - 1);

  return undef if(!$seq);

  return Bio::Seq->new(
	       -DISPLAY_ID => $self->stable_id,
	       -MOLTYPE    => 'dna',
	       -SEQ        => $seq);
}


sub three_prime_utr {
  my $self = shift;

  my $seq = substr($self->spliced_seq, $self->cdna_coding_end);

  return undef if(!$seq);

  return Bio::Seq->new(
	       -DISPLAY_ID => $self->stable_id,
	       -MOLTYPE    => 'dna',
	       -SEQ        => $seq);
}


=head2 get_all_translateable_Exons

  Args       : none
  Example    : none
  Description: Returns a list of exons that translate with the
               start and end exons truncated to the CDS regions.
  Returntype : listref Bio::EnsEMBL::Exon
  Exceptions : throw if translation has invalid information
  Caller     : Genebuild, $self->translate()

=cut


sub get_all_translateable_Exons {
  my ( $self ) = @_;

  #return an empty list if there is no translation (i.e. pseudogene)
  my $translation = $self->translation or return [];  
  my $start_exon      = $translation->start_Exon;
  my $end_exon        = $translation->end_Exon;
  my $t_start         = $translation->start;
  my $t_end           = $translation->end;

  my( @translateable );

  foreach my $ex (@{$self->get_all_Exons}) {

    if ($ex ne $start_exon and ! @translateable) {
      next;   # Not yet in translated region
    }

    my $length  = $ex->length;
        
    my $adjust_start = 0;
    my $adjust_end = 0;
    # Adjust to translation start if this is the start exon
    if ($ex == $start_exon ) {
      if ($t_start < 1 or $t_start > $length) {
        throw("Translation start '$t_start' is outside exon $ex length=$length");
      }
      $adjust_start = $t_start - 1;
    }
        
    # Adjust to translation end if this is the end exon
    if ($ex == $end_exon) {
      if ($t_end < 1 or $t_end > $length) {
        throw("Translation end '$t_end' is outside exon $ex length=$length");
      }
      $adjust_end = $t_end - $length;
    }

    # Make a truncated exon if the translation start or
    # end causes the coordinates to be altered.
    if ($adjust_end || $adjust_start) {
      my $newex = $ex->adjust_start_end( $adjust_start, $adjust_end );

      push( @translateable, $newex );
    } else {
      push(@translateable, $ex);
    }

    # Exit the loop when we've found the last exon
    last if $ex eq $end_exon;
  }
  return \@translateable;
}



# needs selenocystein - U
# use attributes from Translation
# maybe API call ?

=head2 translate

  Args       : none
  Example    : none
  Description: return the peptide (plus eventuel stop codon) for this 
               transcript. Does N padding of non phase matching exons. 
               It uses translateable_seq internally. 
  Returntype : Bio::Seq
  Exceptions : If no Translation is set in this Transcript
  Caller     : general

=cut

sub translate {
  my ($self) = @_;

  my $mrna = $self->translateable_seq();
  my $display_id;
  if( defined $self->translation->stable_id ) {
    $display_id = $self->translation->stable_id;
  } elsif ( defined $self->translation->dbID ) {
    $display_id = $self->translation->dbID();
  } else {
    #use memory location as temp id
    $display_id = scalar($self->translation());
  }

  if( CORE::length( $mrna ) % 3 == 0 ) {
    $mrna =~ s/TAG$|TGA$|TAA$//i;
  }
  # the above line will remove the final stop codon from the mrna
  # sequence produced if it is present, this is so any peptide produced
  # won't have a terminal stop codon
  # if you want to have a terminal stop codon either comment this line out
  # or call translatable seq directly and produce a translation from it

  my $peptide = Bio::Seq->new( -seq => $mrna,
                               -moltype => "dna",
                               -alphabet => 'dna',
                               -id => $display_id );

  return $self->translation->modify_translation( $peptide->translate() );
}

=head2 seq

Returns a Bio::Seq object which consists of just
the sequence of the exons concatenated together,
without messing about with padding with N\'s from
Exon phases like B<dna_seq> does.

=cut

sub seq {
  my( $self ) = @_;
  return Bio::Seq->new
    (-DISPLAY_ID => $self->stable_id,
     -MOLTYPE    => 'dna',
     -SEQ        => $self->spliced_seq);
}


=head2 pep2genomic

  Description: See Bio::EnsEMBL::TranscriptMapper::pep2genomic

=cut

sub pep2genomic {
  my $self = shift;
  return $self->get_TranscriptMapper()->pep2genomic(@_);
}


=head2 genomic2pep

  Description: See Bio::EnsEMBL::TranscriptMapper::genomic2pep

=cut

sub genomic2pep {
  my $self = shift;
  return $self->get_TranscriptMapper()->genomic2pep(@_);
}


=head2 cdna2genomic

  Description: See Bio::EnsEMBL::TranscriptMapper::cdna2genomic

=cut

sub cdna2genomic {
  my $self = shift;
  return $self->get_TranscriptMapper()->cdna2genomic(@_);
}

=head2 genomic2cdna

  Description: See Bio::EnsEMBL::TranscriptMapper::genomic2cdna

=cut

sub genomic2cdna {
  my $self = shift;
  return $self->get_TranscriptMapper->genomic2cdna(@_);
}

=head2 get_TranscriptMapper

  Args       : none
  Example    : my $trans_mapper = $transcript->get_TranscriptMapper();
  Description: Gets a TranscriptMapper object which can be used to perform
               a variety of coordinate conversions relating this transcript,
               genomic sequence and peptide resulting from this transcripts
               translation.
  Returntype : Bio::EnsEMBL::TranscriptMapper
  Exceptions : none
  Caller     : cdna2genomic, pep2genomic, genomic2cdna, cdna2genomic

=cut

sub get_TranscriptMapper {
  my ( $self ) = @_;
  $self->{'transcript_mapper'} ||= Bio::EnsEMBL::TranscriptMapper->new($self);
  return $self->{'transcript_mapper'};
}



=head2 start_Exon

 Title   : start_Exon
 Usage   : $start_exon = $transcript->start_Exon;
 Returns : The first exon in the transcript.
 Args    : NONE

=cut

sub start_Exon{
   my ($self,@args) = @_;

   return $self->get_all_Exons()->[0];
}

=head2 end_Exon

 Title   : end_exon
 Usage   : $end_exon = $transcript->end_Exon;
 Returns : The last exon in the transcript.
 Args    : NONE

=cut

sub end_Exon{
   my ($self,@args) = @_;

   return $self->get_all_Exons()->[-1];
}



=head2 description

 Title   : description
 Usage   : $obj->description($newval)
 Function: 
 Returns : value of description
 Args    : newvalue (optional)


=cut

sub description{
   my $obj = shift;
   if( @_ ) {
      my $value = shift;
      $obj->{'description'} = $value;
    }
    return $obj->{'description'};
}


=head2 version

 Title   : version
 Usage   : $obj->version()
 Function: 
 Returns : value of version
 Args    : 

=cut

sub version{
    my $self = shift;

    $self->{'version'} = shift if( @_ );

    return $self->{'version'};
}


=head2 stable_id

 Title   : stable_id
 Usage   : $obj->stable_id
 Function: 
 Returns : value of stable_id
 Args    : 


=cut

sub stable_id{
    my $self = shift;

    $self->{'stable_id'} = shift if( @_ );

    return $self->{'stable_id'};
}



=head2 swap_exons

  Arg [1]    : Bio::EnsEMBL::Exon $old_Exon
               An exon that should be replaced
  Arg [2]    : Bio::EnsEMBL::Exon $new_Exon
               The replacement Exon
  Example    : none
  Description: exchange an exon in the current Exon list with a given one.
               Usually done before storing of Gene, so the Exons can
               be shared between Transcripts.
  Returntype : none
  Exceptions : none
  Caller     : GeneAdaptor->store()

=cut

sub swap_exons {
  my ( $self, $old_exon, $new_exon ) = @_;
  
  my $arref = $self->{'_trans_exon_array'};
  for(my $i = 0; $i < @$arref; $i++) {
    if($arref->[$i] == $old_exon) {
      $arref->[$i] = $new_exon;
      last;
    }
  }

  if( defined $self->{'translation'} ) {
     if( $self->translation()->start_Exon() == $old_exon ) {
      $self->translation()->start_Exon( $new_exon );
    }
    if( $self->translation()->end_Exon() == $old_exon ) {
      $self->translation()->end_Exon( $new_exon );
    }
  }
}

=head2 transform

  Arg  1     : String $coordinate_system_name
  Arg [2]    : String $coordinate_system_version
  Example    : $transcript = $transcript->transform('contig');
               $transcript = $transcript->transform('chromosome', 'NCBI33');
  Description: Moves this Transcript to the given coordinate system.
               If this Transcript has Exons attached, they move as well.
               A new Transcript is returned. If the transcript cannot be
               transformed to the destination coordinate system undef is
               returned instead.
  Returntype : Bio::EnsEMBL::Transcript
  Exceptions : wrong parameters
  Caller     : general

=cut


sub transform {
  my $self = shift;

  # catch for old style transform calls
  if( ref $_[0] eq 'HASH') {
    deprecate("Calling transform with a hashref is deprecate.\n" .
              'Use $trans->transfer($slice) or ' .
              '$trans->transform("coordsysname") instead.');
    my (undef, $new_ex) = each(%{$_[0]});
    return $self->transfer($new_ex->slice);
  }

  my $new_transcript = $self->SUPER::transform( @_ );
  return undef unless $new_transcript;

  if( defined $self->{'translation'} ) {
    my $new_translation;
    %$new_translation = %{$self->{'translation'}};;
    bless $new_translation, ref( $self->{'translation'} );
    $new_transcript->{'translation'} = $new_translation;
  }

  if( exists $self->{'_trans_exon_array'} ) {
    my @new_exons;
    for my $old_exon ( @{$self->{'_trans_exon_array'}} ) {
      my $new_exon = $old_exon->transform( @_ );
      if( defined $new_transcript->{'translation'} ) {
        if( $new_transcript->translation()->start_Exon() == $old_exon ) {
          $new_transcript->translation()->start_Exon( $new_exon );
        }
        if( $new_transcript->translation()->end_Exon() == $old_exon ) {
          $new_transcript->translation()->end_Exon( $new_exon );
        }
      }
      push( @new_exons, $new_exon );
    }
    $new_transcript->{'_trans_exon_array'} = \@new_exons;
  }

  #flush internal values that depend on the exon coords that may have been
  #cached
  $new_transcript->{'transcript_mapper'} = undef;
  $new_transcript->{'coding_region_start'} = undef;
  $new_transcript->{'coding_region_end'} = undef;
  $new_transcript->{'cdna_coding_start'} = undef;
  $new_transcript->{'cdna_coding_end'} = undef;

  return $new_transcript;
}


=head2 transfer

  Arg  1     : Bio::EnsEMBL::Slice $destination_slice
  Example    : $transcript = $transcript->transfer($slice);
  Description: Moves this transcript to the given slice.
               If this Transcripts has Exons attached, they move as well.
  Returntype : Bio::EnsEMBL::Transcript
  Exceptions : none
  Caller     : general

=cut


sub transfer {
  my $self = shift;

  my $new_transcript = $self->SUPER::transfer( @_ );
  return undef unless $new_transcript;

  if( defined $self->{'translation'} ) {
    my $new_translation;
    %$new_translation = %{$self->{'translation'}};;
    bless $new_translation, ref( $self->{'translation'} );
    $new_transcript->{'translation'} = $new_translation;
  }

  if( exists $self->{'_trans_exon_array'} ) {
    my @new_exons;
    for my $old_exon ( @{$self->{'_trans_exon_array'}} ) {
      my $new_exon = $old_exon->transfer( @_ );
      if( defined $new_transcript->{'translation'} ) {
        if( $new_transcript->translation()->start_Exon() == $old_exon ) {
          $new_transcript->translation()->start_Exon( $new_exon );
        }
        if( $new_transcript->translation()->end_Exon() == $old_exon ) {
          $new_transcript->translation()->end_Exon( $new_exon );
        }
      }
      push( @new_exons, $new_exon );
    }

    $new_transcript->{'_trans_exon_array'} = \@new_exons;
  }

  #flush internal values that depend on the exon coords that may have been
  #cached
  $new_transcript->{'transcript_mapper'} = undef;
  $new_transcript->{'coding_region_start'} = undef;
  $new_transcript->{'coding_region_end'} = undef;
  $new_transcript->{'cdna_coding_start'} = undef;
  $new_transcript->{'cdna_coding_end'} = undef;

  return $new_transcript;
}




=head recalculate_coordinates

  Args       : none
  Example    : none
  Description: called when exon coordinate change happened to recalculate the
               coords of the transcript.  This method should be called if one
               of the exons has been changed.
  Returntype : none
  Exceptions : none
  Caller     : internal

=cut

sub recalculate_coordinates {
  my $self = shift;

  my $exons = $self->get_all_Exons();

  return if(!$exons || !@$exons);

  my ( $slice, $start, $end, $strand );
  $slice = $exons->[0]->slice();
  $strand = $exons->[0]->strand();
  $start = $exons->[0]->start();
  $end = $exons->[0]->end();

  my $transsplicing = 0;

  for my $e ( @$exons ) {
    if( $e->start() < $start ) {
      $start = $e->start();
    }

    if( $e->end() > $end ) {
      $end = $e->end();
    }

    if( $slice && $e->slice() && $e->slice()->name() ne $slice->name() ) {
      throw( "Exons with different slices not allowed on one Transcript" );
    }

    if( $e->strand() != $strand ) {
      $transsplicing = 1;
    }
  }
  if( $transsplicing ) {
    warning( "Transcript contained trans splicing event" );
  }

  $self->start( $start );
  $self->end( $end );
  $self->strand( $strand );
  $self->slice( $slice );

  #flush internal values that depend on the exon coords that may have been
  #cached
  $self->{'transcript_mapper'} = undef;
  $self->{'coding_region_start'} = undef;
  $self->{'coding_region_end'} = undef;
  $self->{'cdna_coding_start'} = undef;
  $self->{'cdna_coding_end'} = undef;
}




=head2 display_id

  Arg [1]    : none
  Example    : print $transcript->display_id();
  Description: This method returns a string that is considered to be
               the 'display' identifier.  For transcripts this is the 
               stable id if it is available otherwise it is an empty string.
  Returntype : string
  Exceptions : none
  Caller     : web drawing code

=cut

sub display_id {
  my $self = shift;
  return $self->{'stable_id'} || '';
}


###########################
# DEPRECATED METHODS FOLLOW
###########################

# _translation_id
# Usage   : DEPRECATED - not needed anymore



=head2 sort

  Description: DEPRECATED.  This method is no longer needed.  Exons are sorted
               automatically when added to the transcript.

=cut

sub sort {
  my $self = shift;

  deprecate( "Exons are kept sorted, you dont have to call sort any more" );
  # Fetch all the features
  my @exons = @{$self->get_all_Exons()};
  
  # Empty the feature table
  $self->flush_Exons();

  # Now sort the exons and put back in the feature table
  my $strand = $exons[0]->strand;

  if ($strand == 1) {
    @exons = sort { $a->start <=> $b->start } @exons;
  } elsif ($strand == -1) {
    @exons = sort { $b->start <=> $a->start } @exons;
  }

  foreach my $e (@exons) {
    $self->add_Exon($e);
  }
}


sub _translation_id {
   my $self = shift;
   deprecate( "This method shouldnt be necessary any more" );
   if( @_ ) {
      my $value = shift;
      $self->{'_translation_id'} = $value;
    }
    return $self->{'_translation_id'};

}

=head2 created

 Description: DEPRECATED - this attribute is not part of transcript anymore

=cut

sub created{
   my $obj = shift;
   deprecate( "This attribute is no longer supported" );
   if( @_ ) {
      my $value = shift;
      $obj->{'created'} = $value;
    }
    return $obj->{'created'};
}


=head2 modified

  Description: DEPRECATED - this attribute is not part of transcript anymore

=cut

sub modified{
   my $obj = shift;
   deprecate( "This attribute is no longer supported" );
   if( @_ ) {
      my $value = shift;
      $obj->{'modified'} = $value;
    }
    return $obj->{'modified'};
}

=head2 temporary_id

 Function: DEPRECATED: Use dbID or stable_id or something else instead

=cut

sub temporary_id{
   my ($obj,$value) = @_;
   deprecate( "I cant see what a temporary_id is good for, please use dbID" .
               "or stableID or\ntry without an id." );
   if( defined $value) {
      $obj->{'temporary_id'} = $value;
    }
    return $obj->{'temporary_id'};
}



1;
