# EnsEMBL Transcript reading writing adaptor for mySQL
#
# Copyright EMBL-EBI 2001
#
# Author: Arne Stabenau
# based on 
# Elia Stupkas Gene_Obj
# 
# Date : 20.02.2001
#

=head1 NAME

Bio::EnsEMBL::DBSQL::TranscriptAdaptor - An adaptor which performs database
interaction relating to the storage and retrieval of Transcripts

=head1 DESCRIPTION

This adaptor provides a means to retrieve and store information related to 
Transcripts.  Primarily this involves the retrieval or storage of 
Bio::EnsEMBL::Transcript objects from a database.  
See Bio::EnsEMBL::Transcript for details of the Transcript class.

=head1 SYNOPSIS

  $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(...);
  $slice_adaptor = $db->get_SliceAdaptor();

  $transcript_adaptor = $db->get_TranscriptAdaptor();

  $transcript = $transcript_adaptor->fetch_by_dbID(1234);

  $transcript = $transcript_adaptor->fetch_by_stable_id('ENST00000201961');
  
  $slice = $slice_adaptor->fetch_by_region('chromosome', '3', 1, 1000000);
  @transcripts = @{$transcript_adaptor->fetch_all_by_Slice($slice)};

  ($transcript) = @{$transcript_adaptor->fetch_all_by_external_name('BRCA2')};


=head1 CONTACT

  Post questions/comments to the EnsEMBL development list:
  ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut

package Bio::EnsEMBL::DBSQL::TranscriptAdaptor;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Translation;

use Bio::EnsEMBL::Utils::Exception qw( deprecate throw warning );

@ISA = qw( Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor );




# _tables
#
#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED implementation of superclass abstract method
#               returns the names, aliases of the tables to use for queries
#  Returntype : list of listrefs of strings
#  Exceptions : none
#  Caller     : internal


sub _tables {
  my $self = shift;

  return ([ 'transcript', 't' ], [ 'transcript_stable_id', 'tsi' ],
	  [ 'xref', 'x' ], [ 'external_db' , 'exdb' ] );
}


#_columns
#
#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED implementation of superclass abstract method
#               returns a list of columns to use for queries
#  Returntype : list of strings
#  Exceptions : none
#  Caller     : internal

sub _columns {
  my $self = shift;

  return qw( t.transcript_id t.seq_region_id t.seq_region_start t.seq_region_end 
	     t.seq_region_strand t.gene_id 
             t.display_xref_id tsi.stable_id tsi.version UNIX_TIMESTAMP(created_date)
             UNIX_TIMESTAMP(modified_date) t.description t.biotype t.confidence
             x.display_label exdb.db_name exdb.status );
}


sub _left_join {
  return ( [ 'transcript_stable_id', "tsi.transcript_id = t.transcript_id" ],
	   [ 'xref', "x.xref_id = t.display_xref_id" ],
	   [ 'external_db', "exdb.external_db_id = x.external_db_id" ] ); 
}



=head2 fetch_by_stable_id

  Arg [1]    : string $stable_id 
               The stable id of the transcript to retrieve
  Example    : $trans = $trans_adptr->fetch_by_stable_id('ENST00000309301');
  Description: Retrieves a transcript via its stable id
  Returntype : Bio::EnsEMBL::Transcript
  Exceptions : none
  Caller     : general

=cut

sub fetch_by_stable_id{
   my ($self,$id) = @_;

   # because of the way this query is constructed (with a left join to the
   # transcript_stable_id table), it is faster to do 2 queries, getting the 
   # transcript_id in the first query
   my $sth = $self->prepare("SELECT transcript_id from transcript_stable_id ". 
                            "WHERE  stable_id = ?");
   $sth->execute($id);

   my ($dbID) = $sth->fetchrow_array();

   return undef if(!$dbID);

   return $self->fetch_by_dbID($dbID);

}



=head2 fetch_by_translation_stable_id

  Arg [1]    : string $transl_stable_id
               The stable identifier of the translation of the transcript to 
               retrieve
  Example    : $t = $tadptr->fetch_by_translation_stable_id('ENSP00000311007');
  Description: Retrieves a Transcript object using the stable identifier of
               its translation.
  Returntype : Bio::EnsEMBL::Transcript
  Exceptions : none
  Caller     : general

=cut

sub fetch_by_translation_stable_id {
  my ($self, $transl_stable_id ) = @_;

  my $sth = $self->prepare( "SELECT t.transcript_id " .
                            "FROM   translation_stable_id tsi, translation t ".
                            "WHERE  tsi.stable_id = ? " .
                            "AND    t.translation_id = tsi.translation_id");

  $sth->execute("$transl_stable_id");

  my ($id) = $sth->fetchrow_array;
  $sth->finish;
  if ($id){
    return $self->fetch_by_dbID($id);
  } else {
    return undef;
  }
}


=head2 fetch_by_translation_id

  Arg [1]    : int $id
               The internal identifier of the translation whose transcript
               is to be retrieved.
  Example    : $tr = $tr_adaptor->fetch_by_translation_id($transl->dbID());
  Description: Given the internal identifier of a translation this method 
               retrieves the transcript associated with that translation.
               If the transcript cannot be found undef is returned instead.
  Returntype : Bio::EnsEMBL::Transcript or undef
  Exceptions : none
  Caller     : general

=cut

sub fetch_by_translation_id {
  my $self = shift;
  my $id   = shift;

  throw("id argument is required.") if(!$id);

  my $sth = $self->prepare( "SELECT t.transcript_id " .
                            "FROM   translation t ".
                            "WHERE  t.translation_id = ?");

  $sth->execute($id);

  my ($dbID) = $sth->fetchrow_array;
  $sth->finish;
  if ($dbID){
    return $self->fetch_by_dbID($dbID);
  } else {
    return undef;
  }
}



=head2 fetch_all_by_Gene

  Arg [1]    : Bio::EnsEMBL::Gene $gene
  Example    : none
  Description: retrieves Transcript objects for given gene. Puts Genes slice
               in each Transcript. 
  Returntype : listref Bio::EnsEMBL::Transcript
  Exceptions : none
  Caller     : Gene->get_all_Transcripts()

=cut


sub fetch_all_by_Gene {
  my $self = shift;
  my $gene = shift;

  my $constraint = "t.gene_id = ".$gene->dbID();

  # Use the fetch_all_by_Slice_constraint method because it
  # handles the difficult Haps/PARs and coordinate remapping

  # Get a slice that entirely overlaps the gene.  This is because we
  # want all transcripts to be retrieved, not just ones overlapping
  # the slice the gene is on (the gene may only partially overlap the slice)
  # For speed reasons, only use a different slice if necessary though.

  my $gslice = $gene->slice();
  my $slice;

  if(!$gslice) {
    throw("Gene must have attached slice to retrieve transcripts.");
  }

  if($gene->start() < 1 || $gene->end() > $gslice->length()) {
    $slice = $self->db->get_SliceAdaptor->fetch_by_Feature($gene);
  } else {
    $slice = $gslice;
  }

  my $transcripts = $self->fetch_all_by_Slice_constraint($slice,$constraint);

  if($slice != $gslice) {
    my @out;
    foreach my $tr (@$transcripts) {
      push @out, $tr->transfer($gslice);
    }
    $transcripts = \@out;
  }


  return $transcripts;
}



=head2 fetch_all_by_Slice

  Arg [1]    : Bio::EnsEMBL::Slice $slice
               The slice to fetch transcripts on.
  Arg [3]    : (optional) boolean $load_exons
               if true, exons will be loaded immediately rather than
               lazy loaded later.
  Example    : $transcripts = $
  Description: Overrides superclass method to optionally load exons
               immediately rather than lazy-loading them later.  This
               is more efficient when there are a lot of transcripts whose
               exons are going to be used.
  Returntype : reference to list of transcripts
  Exceptions : thrown if exon cannot be placed on transcript slice
  Caller     : Slice::get_all_Transcripts

=cut

sub fetch_all_by_Slice {
  my $self  = shift;
  my $slice = shift;
  my $load_exons = shift;

  my $transcripts = $self->SUPER::fetch_all_by_Slice($slice);

  # if there are 0 or 1 transcripts still do lazy-loading
  if(!$load_exons || @$transcripts < 2) {
    return $transcripts;
  }

  # preload all of the exons now, instead of lazy loading later
  # faster than 1 query per transcript

  # first check if the exons are already preloaded
  return $transcripts if( exists $transcripts->[0]->{'_trans_exon_array'});


  # get extent of region spanned by transcripts
  my ($min_start, $max_end);
  foreach my $tr (@$transcripts) {
    if(!defined($min_start) || $tr->seq_region_start() < $min_start) {
      $min_start = $tr->seq_region_start();
    }
    if(!defined($max_end) || $tr->seq_region_end() > $max_end) {
      $max_end   = $tr->seq_region_end();
    }
  }

  my $ext_slice;

  if($min_start >= $slice->start() && $max_end <= $slice->end()) {
    $ext_slice = $slice;
  } else {
    my $sa = $self->db()->get_SliceAdaptor();
    $ext_slice = $sa->fetch_by_region
      ($slice->coord_system->name(), $slice->seq_region_name(),
       $min_start,$max_end, $slice->strand(), $slice->coord_system->version());
  }

  # associate exon identifiers with transcripts

  my %tr_hash = map {$_->dbID => $_} @$transcripts;

  my $tr_id_str = '(' . join(',', keys %tr_hash) . ')';

  my $sth = $self->prepare("SELECT transcript_id, exon_id, rank " .
                           "FROM   exon_transcript " .
                           "WHERE  transcript_id IN $tr_id_str");

  $sth->execute();

  my ($ex_id, $tr_id, $rank);
  $sth->bind_columns(\$tr_id, \$ex_id, \$rank);

  my %ex_tr_hash;

  while($sth->fetch()) {
    $ex_tr_hash{$ex_id} ||= [];
    push @{$ex_tr_hash{$ex_id}}, [$tr_hash{$tr_id}, $rank];
  }

  $sth->finish();

  my $ea = $self->db()->get_ExonAdaptor();
  my $exons = $ea->fetch_all_by_Slice($ext_slice);

  # move exons onto transcript slice, and add them to transcripts
  foreach my $ex (@$exons) {

    my $new_ex;
    if($slice != $ext_slice) {
      $new_ex = $ex->transfer($slice) if($slice != $ext_slice);
      if(!$new_ex) {
	throw("Unexpected. Exon could not be transfered onto transcript slice.");
      }
    } else {
      $new_ex = $ex;
    }

    foreach my $row (@{$ex_tr_hash{$new_ex->dbID()}}) {
      my ($tr, $rank) = @$row;
      $tr->add_Exon($new_ex, $rank);
    }
  }

  my $tla = $self->db()->get_TranslationAdaptor();

  # load all of the translations at once
  $tla->fetch_all_by_Transcript_list($transcripts);

  return $transcripts;
}



=head2 fetch_all_by_external_name

  Arg [1]    : string $external_id
               An external identifier of the transcript to be obtained
  Example    : @trans = @{$tr_adaptor->fetch_all_by_external_name('ARSE')};
  Description: Retrieves all transcripts which are associated with an 
               external identifier such as a GO term, HUGO id, Swissprot
               identifer, etc.  Usually there will only be a single transcript
               returned in the listref, but not always.  Transcripts are
               returned in their native coordinate system.  That is, the 
               coordinate system in which they are stored in the database. If
               they are required in another coordinate system the 
               Transcript::transfer or Transcript::transform method can be 
               used to convert them.  If no transcripts with the external
               identifier are found, a reference to an empty list is returned.
  Returntype : reference to a list of transcripts
  Exceptions : none
  Caller     : general

=cut

sub fetch_all_by_external_name {
  my $self = shift;
  my $external_id = shift;

  my @trans = ();

  my $entryAdaptor = $self->db->get_DBEntryAdaptor();
  my @ids = $entryAdaptor->list_transcript_ids_by_extids($external_id);

  return $self->fetch_all_by_dbID_list(\@ids);
}


=head2 fetch_by_display_label

  Arg [1]    : string $label
  Example    : my $transcript = $transcriptAdaptor->fetch_by_display_label( "BRCA2" );
  Description: returns the transcript which has the given display label or undef if
               there is none. If there are more than 1, only the first is reported.
  Returntype : Bio::EnsEMBL::Transcript
  Exceptions : none
  Caller     : general

=cut

sub fetch_by_display_label {
  my $self = shift;
  my $label = shift;

  my ( $transcript ) = @{$self->generic_fetch( "x.display_label = \"$label\"" )};
  return $transcript;
}


=head2 fetch_all_by_exon_stable_id

  Arg [1]    : string $stable_id 
               The stable id of an exon in a transcript
  Example    : $trans = $trans_adptr->fetch_all_by_exon_stable_id('ENSE00000309301');
  Description: Retrieves a list of transcripts via an exon stable id
  Returntype : Bio::EnsEMBL::Transcript
  Exceptions : none
  Caller     : general

=cut

sub fetch_all_by_exon_stable_id {
  my ($self, $stable_id ) = @_;
  my @trans ;
  my $sth = $self->prepare( qq(	SELECT et.transcript_id 
				FROM exon_transcript as et, 
				exon_stable_id as esi 
				WHERE esi.exon_id = et.exon_id and 
				esi.stable_id = ?  ));
  $sth->execute("$stable_id");

  while( my $id = $sth->fetchrow_array ) {
    my $transcript = $self->fetch_by_dbID( $id  );
    push(@trans, $transcript) if $transcript;
  }

  if (!@trans) {
    return undef;
  }

  return \@trans;
}


=head2 store

  Arg [1]    : Bio::EnsEMBL::Transcript $transcript
               The transcript to be written to the database
  Arg [2]    : int $gene_dbID
               The identifier of the gene that this transcript is associated 
               with
  Example    : $transID = $transcriptAdaptor->store($transcript, $gene->dbID);
  Description: Stores a transcript in the database and returns the new
               internal identifier for the stored transcript.
  Returntype : int 
  Exceptions : none
  Caller     : general

=cut

sub store {
   my ($self,$transcript,$gene_dbID) = @_;

   if( ! ref $transcript || !$transcript->isa('Bio::EnsEMBL::Transcript') ) {
     throw("$transcript is not a EnsEMBL transcript - not storing");
   }

   my $db = $self->db();

   if($transcript->is_stored($db)) {
     return $transcript->dbID();
   }

   #force lazy-loading of exons and ensure coords are correct
   $transcript->recalculate_coordinates();

   #
   # Store exons - this needs to be done before the possible transfer
   # of the transcript to another slice (in _prestore()).Transfering results
   # in copies  being made of the exons and we need to preserve the object
   # identity of the exons so that they are not stored twice by different
   # transcripts.
   #
   my $exons = $transcript->get_all_Exons();
   my $exonAdaptor = $db->get_ExonAdaptor();
   foreach my $exon ( @{$exons} ) {
     $exonAdaptor->store( $exon );
   }

   my $original_translation = $transcript->translation();
   my $original = $transcript;
   my $seq_region_id;
   ($transcript, $seq_region_id) = $self->_pre_store($transcript);

   # first store the transcript w/o a display xref
   # the display xref needs to be set after xrefs are stored which needs to
   # happen after transcript is stored...

   my $xref_id = undef;

   #
   #store transcript
   #
   my $tst = $self->prepare(
        "insert into transcript ( gene_id, seq_region_id, seq_region_start, " .
			    "seq_region_end, seq_region_strand, biotype, " .
			    "confidence, description ) ".
			    "values ( ?, ?, ?, ?, ?, ?, ?, ? )");

   $tst->execute( $gene_dbID, $seq_region_id, $transcript->start(),
                  $transcript->end(), $transcript->strand(), 
		  $transcript->biotype(), $transcript->confidence(),
		  $transcript->description() );

   $tst->finish();

   my $transc_dbID = $tst->{'mysql_insertid'};

   #
   # store translation
   #
   my $translation = $transcript->translation();
   if( defined $translation ) {
     #make sure that the start and end exon are set correctly
     my $start_exon = $translation->start_Exon();
     my $end_exon   = $translation->end_Exon();

     if(!$start_exon) {
       throw("Translation does not define a start exon.");
     }

     if(!$end_exon) {
       throw("Translation does not defined an end exon.");
     }

     #If the dbID is not set, this means the exon must have been a different 
     #object in memory than the the exons of the transcript.  Try to find the
     #matching exon in all of the exons we just stored
     if(!$start_exon->dbID()) {
       my $key = $start_exon->hashkey();
       ($start_exon) = grep {$_->hashkey() eq $key} @$exons;
       
       if($start_exon) {
         $translation->start_Exon($start_exon);
       } else {
         throw("Translation's start_Exon does not appear to be one of the " .
               "exons in its associated Transcript");
       }
     }

     if(!$end_exon->dbID()) {
       my $key = $end_exon->hashkey();
       ($end_exon) = grep {$_->hashkey() eq $key} @$exons;

       if($start_exon) {
         $translation->end_Exon($end_exon);
       } else {
         throw("Translation's end_Exon does not appear to be one of the " .
               "exons in its associated Transcript.");
       }
     }

     $db->get_TranslationAdaptor()->store( $translation, $transc_dbID );
     # set values of the original translation, we may have copied it
     # when we transformed the transcript
     $original_translation->dbID($translation->dbID());
     $original_translation->adaptor($translation->adaptor());
   }

   #
   # store the xrefs/object xref mapping
   #
   my $dbEntryAdaptor = $db->get_DBEntryAdaptor();

   foreach my $dbe ( @{$transcript->get_all_DBEntries} ) {
     $dbEntryAdaptor->store( $dbe, $transc_dbID, "Transcript" );
   }

   #
   # Update transcript to point to display xref if it is set
   #
   if(my $dxref = $transcript->display_xref) {
     my $dxref_id;

     if($dxref->is_stored($db)) {
       $dxref_id = $dxref->dbID();
     } else {
       $dxref_id = $dbEntryAdaptor->exists($dxref);
     }

     if(defined($dxref_id)) {
       my $sth = $self->prepare( "update transcript set display_xref_id = ?".
                                 " where transcript_id = ?");
       $sth->execute($dxref_id, $transc_dbID);
       $dxref->dbID($dxref_id);
       $dxref->adaptor($dbEntryAdaptor);
       $sth->finish();
     } else {
       warning("Display_xref ".$dxref->dbname().":".$dxref->display_id() .
               " is not stored in database.\nNot storing " .
               "relationship to this transcript.");
       $dxref->dbID(undef);
       $dxref->adaptor(undef);
     }
   }

   #
   # Link transcript to exons in exon_transcript table
   #
   my $etst =
     $self->prepare("insert into exon_transcript (exon_id,transcript_id,rank)"
                    ." values (?,?,?)");
   my $rank = 1;
   foreach my $exon ( @{$transcript->get_all_Exons} ) {
     $etst->execute($exon->dbID,$transc_dbID,$rank);
     $rank++;
   }

   $etst->finish();

   #
   # Store stable_id
   #
   if (defined($transcript->stable_id)) {
     if (!defined($transcript->version)) {
       throw("Trying to store incomplete stable id information for " .
                    "transcript");
     }

     my $statement = 
       "INSERT INTO transcript_stable_id ".
	 "SET transcript_id = ?, ".
	   "  stable_id = ?, ".
	     "version = ?, ";

     if( $transcript->created_date() ) {
       $statement .= "created_date = from_unixtime( ".$transcript->created_date()."),";
     } else {
       $statement .= "created_date = \"0000-00-00 00:00:00\",";
     }

     if( $transcript->modified_date() ) {
       $statement .= "modified_date = from_unixtime( ".$transcript->modified_date().")";
     } else {
       $statement .= "modified_date = \"0000-00-00 00:00:00\"";
     }

     my $sth = $self->prepare($statement);
     $sth->execute($transc_dbID, $transcript->stable_id, $transcript->version);
     $sth->finish();
   }


  # Now the supporting evidence
  # should be stored from featureAdaptor
  my $sql = "insert into transcript_supporting_feature (transcript_id, feature_id, feature_type)
             values(?, ?, ?)";

  my $sf_sth = $self->prepare($sql);

  my $anaAdaptor = $self->db->get_AnalysisAdaptor();
  my $dna_adaptor = $self->db->get_DnaAlignFeatureAdaptor();
  my $pep_adaptor = $self->db->get_ProteinAlignFeatureAdaptor();
  my $type;

  foreach my $sf (@{$transcript->get_all_supporting_features}) {
    if(!$sf->isa("Bio::EnsEMBL::BaseAlignFeature")){
      throw("$sf must be an align feature otherwise" .
            "it can't be stored");
    }

    if($sf->isa("Bio::EnsEMBL::DnaDnaAlignFeature")){
      $dna_adaptor->store($sf);
      $type = 'dna_align_feature';
    }elsif($sf->isa("Bio::EnsEMBL::DnaPepAlignFeature")){
      $pep_adaptor->store($sf);
      $type = 'protein_align_feature';
    } else {
      warning("Supporting feature of unknown type. Skipping : [$sf]\n");
      next;
    }

    $sf_sth->execute($transc_dbID, $sf->dbID, $type);
  }



   #update the original transcript object - not the transfered copy that
   #we might have created
   $original->dbID( $transc_dbID );
   $original->adaptor( $self );

   # store transcript attributes if there are any
   my $attr_adaptor = $db->get_AttributeAdaptor();
   $attr_adaptor->store_on_Transcript($transcript,
                                      $transcript->get_all_Attributes);


   return $transc_dbID;
}






=head2 get_Interpro_by_transid

  Arg [1]    : string $trans
               the stable if of the trans to obtain
  Example    : @i = $trans_adaptor->get_Interpro_by_transid($trans->stable_id()); 
  Description: gets interpro accession numbers by transcript stable id.
               A hack really - we should have a much more structured 
               system than this
  Returntype : listref of strings 
  Exceptions : none 
  Caller     : domainview? , GeneView

=cut

sub get_Interpro_by_transid {
   my ($self,$transid) = @_;

   my $sth = $self->prepare
     ("SELECT  STRAIGHT_JOIN i.interpro_ac, x.description " .
      "FROM    transcript_stable_id tsi, ".
              "translation tl, ".
              "protein_feature pf, ".
		          "interpro i, " .
              "xref x " .
	    "WHERE tsi.stable_id = ? " .
	    "AND   tl.transcript_id = tsi.transcript_id " .
	    "AND	 tl.translation_id = pf.translation_id  " .
	    "AND   i.id = pf.hit_id " .
	    "AND   i.interpro_ac = x.dbprimary_acc");

   $sth->execute($transid);

   my @out;
   my %h;
   while( (my $arr = $sth->fetchrow_arrayref()) ) {
       if( $h{$arr->[0]} ) { next; }
       $h{$arr->[0]}=1;
       my $string = $arr->[0] .":".$arr->[1];
       push(@out,$string);
   }

   return \@out;
}




=head2 remove

  Arg [1]    : Bio::EnsEMBL::Transcript $transcript
  Example    : $transcript_adaptor->remove($transcript);
  Description: Removes a transcript completely from the database, and all
               associated information.
               This method is usually called by the GeneAdaptor::remove method
               because this method will not preform the removal of genes
               which are associated with this transcript.  Do not call this
               method directly unless you know there are no genes associated
               with the transcript!
  Returntype : none
  Exceptions : throw on incorrect arguments
               warning if transcript is not in this database
  Caller     : GeneAdaptor::remove

=cut

sub remove {
  my $self = shift;
  my $transcript = shift;

  if(!ref($transcript) || !$transcript->isa('Bio::EnsEMBL::Transcript')) {
    throw("Bio::EnsEMBL::Transcript argument expected");
  }

  # sanity check: make sure nobody tries to slip past a prediction transcript
  # which inherits from transcript but actually uses different tables
  if($transcript->isa('Bio::EnsEMBL::PredictionTranscript')) {
    throw("TranscriptAdaptor can only remove Transcripts " .
          "not PredictionTranscripts");
  }

  if( !$transcript->is_stored($self->db()) ) {
    warning("Cannot remove transcript ". $transcript->dbID .". Is not stored ".
            "in this database.");
    return;
  }

  # remove all xref linkages to this transcript

  my $dbeAdaptor = $self->db->get_DBEntryAdaptor();
  foreach my $dbe (@{$transcript->get_all_DBEntries}) {
    $dbeAdaptor->remove_from_object($dbe, $transcript, 'Transcript');
  }

  my $exonAdaptor = $self->db->get_ExonAdaptor();
  my $translationAdaptor = $self->db->get_TranslationAdaptor();

  # remove the translation associated with this transcript

  if( defined($transcript->translation()) ) {
    $translationAdaptor->remove( $transcript->translation );
  }

  # remove exon associations to this transcript

  foreach my $exon ( @{$transcript->get_all_Exons()} ) {
    # get the number of transcript references to this exon
    # only remove the exon if this is the last transcript to
    # reference it

    my $sth = $self->prepare( "SELECT count(*)
                               FROM   exon_transcript
                               WHERE  exon_id = ?" );
    $sth->execute( $exon->dbID );
    my ($count) = $sth->fetchrow_array();
    $sth->finish();

    if($count == 1){
      $exonAdaptor->remove( $exon );
    }
  }

  my $sth = $self->prepare( "DELETE FROM exon_transcript
                             WHERE transcript_id = ?" );
  $sth->execute( $transcript->dbID );
  $sth = $self->prepare( "DELETE FROM transcript_stable_id
                          WHERE transcript_id = ?" );
  $sth->execute( $transcript->dbID );
  $sth->finish();


  $sth = $self->prepare( "DELETE FROM transcript
                          WHERE transcript_id = ?" );
  $sth->execute( $transcript->dbID );
  $sth->finish();

  $transcript->dbID(undef);
  $transcript->adaptor(undef);

  return;
}



=head2 update

  Arg [1]    : Bio::EnsEMBL::Transcript
  Example    : $transcript_adaptor->update($transcript);
  Description: Updates a transcript in the database
  Returntype : None
  Exceptions : thrown if the $transcript is not a Bio::EnsEMBL::Transcript
               warn if trying to update the number of attached exons.  This
               is a far more complex process and is not yet implemented.
               warn if the method is called on a transcript that does not exist 
               in the database.
  Caller     : general

=cut

sub update {
   my ($self,$transcript) = @_;
   my $update = 0;

   if( !defined $transcript || !ref $transcript || 
       !$transcript->isa('Bio::EnsEMBL::Transcript') ) {
     throw("Must update a transcript object, not a $transcript");
   }

   my $update_transcript_sql = "
        UPDATE transcript
           SET display_xref_id = ?,
               description = ?,
               biotype = ?,
               confidence = ?
         WHERE transcript_id = ?";

   my $display_xref = $transcript->display_xref();
   my $display_xref_id;

   if( $display_xref && $display_xref->dbID() ) {
     $display_xref_id = $display_xref->dbID();
   } else {
     $display_xref_id = undef;
   }

   my $sth = $self->prepare( $update_transcript_sql );
   $sth->execute( $display_xref_id, $transcript->description(),
		  $transcript->biotype(), $transcript->confidence(),
		  $transcript->dbID() );
 }

=head2 list_dbIDs

  Arg [1]    : none
  Example    : @transcript_ids = @{$transcript_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all transcripts in the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : ?

=cut

sub list_dbIDs {
   my ($self) = @_;

   return $self->_list_dbIDs("transcript");
}

=head2 list_stable_dbIDs

  Arg [1]    : none
  Example    : @stable_trans_ids = @{$transcript_adaptor->list_stable_dbIDs()};
  Description: Gets an array of stable ids for all transcripts in the current
               database.
  Returntype : listref of ints
  Exceptions : none
  Caller     : ?

=cut

sub list_stable_ids {
   my ($self) = @_;

   return $self->_list_dbIDs("transcript_stable_id", "stable_id");
}


#_objs_from_sth

#  Arg [1]    : StatementHandle $sth
#  Example    : none 
#  Description: PROTECTED implementation of abstract superclass method.
#               responsible for the creation of Transcripts
#  Returntype : listref of Bio::EnsEMBL::Transcripts in target coord system
#  Exceptions : none
#  Caller     : internal

sub _objs_from_sth {
  my ($self, $sth, $mapper, $dest_slice) = @_;

  #
  # This code is ugly because an attempt has been made to remove as many
  # function calls as possible for speed purposes.  Thus many caches and
  # a fair bit of gymnastics is used.
  #

  my $sa = $self->db()->get_SliceAdaptor();
  my $dbEntryAdaptor = $self->db()->get_DBEntryAdaptor();

  my @transcripts;
  my %slice_hash;
  my %sr_name_hash;
  my %sr_cs_hash;

  my ( $transcript_id, $seq_region_id, $seq_region_start, $seq_region_end, 
       $seq_region_strand, $gene_id,  
       $display_xref_id, $stable_id, $version, $created_date, $modified_date,
       $description, $biotype, $confidence,
       $external_name, $external_db, $external_status );

  $sth->bind_columns( \$transcript_id, \$seq_region_id, \$seq_region_start, 
                      \$seq_region_end, \$seq_region_strand, \$gene_id,  
                      \$display_xref_id, \$stable_id, \$version, \$created_date, \$modified_date,
		      \$description, \$biotype, \$confidence,
                      \$external_name, \$external_db, \$external_status );



  my $asm_cs;
  my $cmp_cs;
  my $asm_cs_vers;
  my $asm_cs_name;
  my $cmp_cs_vers;
  my $cmp_cs_name;
  if($mapper) {
    $asm_cs = $mapper->assembled_CoordSystem();
    $cmp_cs = $mapper->component_CoordSystem();
    $asm_cs_name = $asm_cs->name();
    $asm_cs_vers = $asm_cs->version();
    $cmp_cs_name = $cmp_cs->name();
    $cmp_cs_vers = $cmp_cs->version();
  }

  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  my $dest_slice_cs;
  my $dest_slice_sr_name;

  my $asma;
  if($dest_slice) {
    $dest_slice_start  = $dest_slice->start();
    $dest_slice_end    = $dest_slice->end();
    $dest_slice_strand = $dest_slice->strand();
    $dest_slice_length = $dest_slice->length();
    $dest_slice_cs     = $dest_slice->coord_system();
    $dest_slice_sr_name = $dest_slice->seq_region_name();

    $asma              = $self->db->get_AssemblyMapperAdaptor();
  }

  FEATURE: while($sth->fetch()) {

    my $slice = $slice_hash{"ID:".$seq_region_id};
    my $dest_mapper = $mapper;

    if(!$slice) {
      $slice = $sa->fetch_by_seq_region_id($seq_region_id);
      $slice_hash{"ID:".$seq_region_id} = $slice;
      $sr_name_hash{$seq_region_id} = $slice->seq_region_name();
      $sr_cs_hash{$seq_region_id} = $slice->coord_system();
    }

    #obtain a mapper if none was defined, but a dest_seq_region was
    if(!$dest_mapper && $dest_slice && 
       !$dest_slice_cs->equals($slice->coord_system)) {
      $dest_mapper = $asma->fetch_by_CoordSystems($dest_slice_cs,
                                                 $slice->coord_system);
      $asm_cs = $dest_mapper->assembled_CoordSystem();
      $cmp_cs = $dest_mapper->component_CoordSystem();
      $asm_cs_name = $asm_cs->name();
      $asm_cs_vers = $asm_cs->version();
      $cmp_cs_name = $cmp_cs->name();
      $cmp_cs_vers = $cmp_cs->version();
    }

    my $sr_name = $sr_name_hash{$seq_region_id};
    my $sr_cs   = $sr_cs_hash{$seq_region_id};
    #
    # remap the feature coordinates to another coord system 
    # if a mapper was provided
    #
    if($dest_mapper) {

      ($sr_name,$seq_region_start,$seq_region_end,$seq_region_strand) =
        $dest_mapper->fastmap($sr_name, $seq_region_start, $seq_region_end,
                              $seq_region_strand, $sr_cs);

      #skip features that map to gaps or coord system boundaries
      next FEATURE if(!defined($sr_name));

      #get a slice in the coord system we just mapped to
      if($asm_cs == $sr_cs || ($cmp_cs != $sr_cs && $asm_cs->equals($sr_cs))) {
        $slice = $slice_hash{"NAME:$sr_name:$cmp_cs_name:$cmp_cs_vers"} ||=
          $sa->fetch_by_region($cmp_cs_name, $sr_name,undef, undef, undef,
                               $cmp_cs_vers);
      } else {
        $slice = $slice_hash{"NAME:$sr_name:$asm_cs_name:$asm_cs_vers"} ||=
          $sa->fetch_by_region($asm_cs_name, $sr_name, undef, undef, undef,
                               $asm_cs_vers);
      }
    }

    #
    # If a destination slice was provided convert the coords
    # If the dest_slice starts at 1 and is foward strand, nothing needs doing
    #
    if($dest_slice) {
      if($dest_slice_start != 1 || $dest_slice_strand != 1) {
        if($dest_slice_strand == 1) {
          $seq_region_start = $seq_region_start - $dest_slice_start + 1;
          $seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
        } else {
          my $tmp_seq_region_start = $seq_region_start;
          $seq_region_start = $dest_slice_end - $seq_region_end + 1;
          $seq_region_end   = $dest_slice_end - $tmp_seq_region_start + 1;
          $seq_region_strand *= -1;
        }
      }

      #throw away features off the end of the requested slice
      if($seq_region_end < 1 || $seq_region_start > $dest_slice_length || 
	( $dest_slice_sr_name ne $sr_name )) {
	next FEATURE;
      }

      $slice = $dest_slice;
    }

    my $display_xref;

    if( $display_xref_id ) {
      $display_xref = Bio::EnsEMBL::DBEntry->new_fast
        ({ 'dbID' => $display_xref_id,
           'adaptor' => $dbEntryAdaptor,
           'display_id' => $external_name,
           'dbname' => $external_db});
    }
				

    #finally, create the new transcript
    push @transcripts, Bio::EnsEMBL::Transcript->new
      ( '-start'         =>  $seq_region_start,
        '-end'           =>  $seq_region_end,
        '-strand'        =>  $seq_region_strand,
        '-adaptor'       =>  $self,
        '-slice'         =>  $slice,
        '-dbID'          =>  $transcript_id,
        '-stable_id'     =>  $stable_id,
        '-version'       =>  $version,
	'-created_date'  =>  $created_date || undef,
	'-modified_date' =>  $modified_date || undef,
        '-external_name' =>  $external_name,
        '-external_db'   =>  $external_db,
        '-external_status' => $external_status,
        '-display_xref'  => $display_xref,
	'-description'   => $description,
	'-biotype'       => $biotype,
	'-confidence'    => $confidence );
  }

  return \@transcripts;
}



=head2 get_display_xref

  Description: DEPRECATED use $transcript->display_xref()

=cut

sub get_display_xref {
  my ($self, $transcript) = @_;
	
  deprecate( "display_xref should be retreived from Transcript object directly." );
  
  if( !defined $transcript ) {
      throw("Must call with a Transcript object");
  }

  my $sth = $self->prepare("SELECT e.db_name,
                                   x.display_label,
                                   x.xref_id
                            FROM   transcript t, 
                                   xref x, 
                                   external_db e
                            WHERE  t.transcript_id = ?
                              AND  t.display_xref_id = x.xref_id
                              AND  x.external_db_id = e.external_db_id
                           ");
  $sth->execute( $transcript->dbID );


  my ($db_name, $display_label, $xref_id ) = $sth->fetchrow_array();
  if( !defined $xref_id ) {
    return undef;
  }

  my $db_entry = Bio::EnsEMBL::DBEntry->new
    (
     -dbid => $xref_id,
     -adaptor => $self->db->get_DBEntryAdaptor(),
     -dbname => $db_name,
     -display_id => $display_label
    );

  return $db_entry;
}




=head2 get_stable_entry_info

  Description: DEPRECATED Use $transcript->stable_id()

=cut

sub get_stable_entry_info {
  my ($self,$transcript) = @_;

  deprecate( "Stable ids should be loaded directly now" );

  unless( defined $transcript && ref $transcript && 
	  $transcript->isa('Bio::EnsEMBL::Transcript') ) {
    throw("Needs a Transcript object, not a $transcript");
  }

  my $sth = $self->prepare("SELECT stable_id, version 
                            FROM   transcript_stable_id 
                            WHERE  transcript_id = ?");
  $sth->execute($transcript->dbID());

  my @array = $sth->fetchrow_array();
  $transcript->{'_stable_id'} = $array[0];
  $transcript->{'_version'}   = $array[1];


  return 1;
}




=head2 fetch_all_by_DBEntry

  Description: DEPRECATED this method has been renamed 
               fetch_all_by_external_name

=cut

sub fetch_all_by_DBEntry {
  my $self = shift;
  deprecate('Use fetch_all_by_external_name instead.');
  return $self->fetch_all_by_external_name(@_);
}


1;

