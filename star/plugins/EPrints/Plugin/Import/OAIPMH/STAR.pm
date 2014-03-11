package EPrints::Plugin::Import::OAIPMH::STAR;

use strict;
use warnings;

use EPrints::Plugin::Import::OAIPMH;

our @ISA = qw/ EPrints::Plugin::Import::OAIPMH /;

sub new
{
	my( $class, %opts ) = @_;

	my $self = $class->SUPER::new( %opts );

	$self->{name} = 'OAI-PMH Importer - STAR - French Thesis';
	$self->{visible} = "none";
	$self->{produce} = [ 'list/eprint', 'dataobj/eprint' ];

	# this will be a parameter when the target URL is harvested
	$self->{metadataPrefix} = 'tef';

	return $self;
}

sub xml_to_epdata
{
	my( $self, $xml ) = @_;

	my @threcs = $xml->getElementsByTagName( 'thesisRecord' );
	return undef unless( EPrints::Utils::is_set( @threcs ) );

	my $thesis = $threcs[0];
	my $epdata = $self->thesis_record_to_epdata( $thesis );

	# also another section to analyse...

	my @thadmins = $xml->getElementsByTagName( 'thesisAdmin' );
	if( scalar(@thadmins) )
	{
		my $thadmin = $thadmins[0];
		my $admin_epdata = $self->thesis_admin_to_epdata( $thadmin );
		foreach( keys %$admin_epdata )
		{
			$epdata->{$_} = $admin_epdata->{$_};
		}
	}

	return $epdata;
}

sub thesis_record_to_epdata
{
	my( $self, $tef ) = @_;

	my $epdata = {};

	my @titles;
	my $title_fr = $self->get_node_content( $tef, 'title', { name => 'xml:lang', value => 'fr' } );
	push @titles, $title_fr if( defined $title_fr );
	my $title_en = $self->get_node_content( $tef, 'title', { name => 'xml:lang', value => 'en' } );
	push @titles, $title_en if( defined $title_en );

	my @alt_titles;
	my $alt_title_fr = $self->get_node_content( $tef, 'alternative', { name => 'xml:lang', value => 'fr' } );
	push @alt_titles, $alt_title_fr if( defined $alt_title_fr );
	my $alt_title_en = $self->get_node_content( $tef, 'alternative', { name => 'xml:lang', value => 'en' } );
	push @alt_titles, $alt_title_en if( defined $alt_title_en );

	$epdata->{title} = \@titles if( scalar( @titles ) );
	$epdata->{alt_title} = \@alt_titles if( scalar( @alt_titles ) );

	my @abstracts;

	# French abstract goes first.	
	my $abstract_fr = $self->get_node_content( $tef, 'abstract', { name => 'xml:lang', value => 'fr' } );
	push @abstracts, $abstract_fr if( defined $abstract_fr );

	my $abstract = $self->get_node_content( $tef, 'abstract', { name => 'xml:lang', value => 'en' } );
	push @abstracts, $abstract if( defined $abstract );

	$epdata->{abstract} = \@abstracts;

	$epdata->{language} = [$self->get_node_content( $tef, 'language' )];
	
	$epdata->{keywords} = $self->get_node_content_multiple( $tef, 'subject', { name => 'xml:lang', value => 'en' } );

	# french_keywords  / Classification 'Rameau'
	my $rameau = $self->get_rameau_subjects( $tef );

	$epdata->{french_keywords} = $rameau if( EPrints::Utils::is_set( $rameau ) );

	return $epdata;
}

sub get_rameau_subjects
{
	my( $self, $tef ) = @_;

	my @subjects;

	my @noms = $tef->getElementsByTagName( 'vedetteRameauNomCommun' );

	foreach my $nom ( @noms )
	{
		my @labels = ( @{$self->get_node_content_multiple( $nom, 'elementdEntree', { name => 'autoriteSource', value => 'Sudoc' } ) || [] },
				@{$self->get_node_content_multiple( $nom, 'subdivision', { name => 'autoriteSource', value => 'Sudoc' } ) || [] }
		);

		next unless( scalar( @labels ) );

		push @subjects, join(" - ", @labels );
	}
	
	return \@subjects;
}

sub thesis_admin_to_epdata
{
	my( $self, $tef ) = @_;

	my $epdata = {};

	my $author = ($tef->getElementsByTagName( 'auteur' ) || [])->[0];
	if( defined $author )
	{
		push @{ $epdata->{creators} }, { name => {
				family => $self->get_node_content( $author, 'nom' ),
				given => $self->get_node_content( $author, 'prenom' )
		}};
	}

	$epdata->{thesis_id} = $self->get_node_content( $tef, 'identifier', { name => 'xsi:type', value => 'tef:NNT' } );
	$epdata->{official_url} = $self->get_node_content( $tef, 'identifier', { name => 'xsi:type', value => 'tef:nationalThesisPID' } );

	$epdata->{viva_date} = $self->get_node_content( $tef, 'dateAccepted', { name => 'xsi:type', value => 'dcterms:W3CDTF' } );

	my @mads = $tef->getElementsByTagName( 'MADSAuthority' );
	
	my %directeurs;
	my %membres;
	my @ecoles;
	my @unites_de_recherche;

	foreach my $md (@mads)
	{
		my $type = $md->getAttribute( 'authorityID' );
		next unless( defined $type );

		if( $type =~ /^MADS_DIRECTEUR_DE_THESE_(\d+)$/ )
		{
			$directeurs{$1} = { name => {
				family => $self->get_node_content( $md, 'namePart', { name => 'type', value => 'family' } ),
				given => $self->get_node_content( $md, 'namePart', { name => 'type', value => 'given' } ),
			} };
		}
		elsif( $type =~ /^MADS_MEMBRE_DU_JURY_(\d+)$/ )
		{
			$membres{$1} = { name => {
				family => $self->get_node_content( $md, 'namePart', { name => 'type', value => 'family' } ),
				given => $self->get_node_content( $md, 'namePart', { name => 'type', value => 'given' } ),
			} };
		}
		elsif( $type =~ /^MADS_ECOLE_DOCTORALE_(\d)+$/ )
		{
			push @ecoles, $self->get_node_content( $md, 'namePart', { name => 'type', value => 'family' } );
		}
		elsif( $type =~ /^MADS_PARTENAIRE_DE_RECHERCHE_(\d)+$/ )
		{
			push @unites_de_recherche, $self->get_node_content( $md, 'namePart', { name => 'type', value => 'family' } );
		}
	}

	foreach( sort keys %directeurs )
	{
		push @{$epdata->{supervisors}}, $directeurs{$_};
	}

	foreach( sort keys %membres )
	{
		push @{$epdata->{examiners}}, $membres{$_};
	}

	my $ecoles_codes = $self->map_strings_to_namedset( 'doctoral_school', \@ecoles );

	# Ecole doctorale - single value
	if( scalar( @$ecoles_codes ) )
	{
		$epdata->{doctoral_school} = $ecoles_codes->[0];
	}

	my $unites_codes = $self->map_strings_to_namedset( 'divisions', \@unites_de_recherche );

	# Divisions / Unites de recherche - multiple values
	if( scalar( @$unites_codes ) )
	{
		$epdata->{divisions} = $unites_codes;
	}

	return $epdata;
}


# will attempt to match a string value back to the namedset code in EPrints
sub map_strings_to_namedset
{
	my( $self, $fieldname, $strings ) = @_;

	my $namedset_values = $self->get_namedset_values( $fieldname );

	my @matches;

	foreach my $string ( @$strings )
	{
		# a bit of a hack, we need to be able to map a string back to a namedset key :-/
		$string = &_normalise_string( $string );

		while( my( $code, $desc ) = each( %$namedset_values ) )
		{
			if( ($string =~ /$desc/i ) || ( $string =~ /$code/i ) )
			{
				push @matches, $code;
				last;
			}
		}
	}

	return \@matches;
}

sub get_namedset_values
{
	my( $self, $fieldname ) = @_;
	
	my $field = $self->{session}->dataset( 'eprint' )->field( "$fieldname" );
	return {} unless( defined $field );

	my %values;
	my @tags = $field->tags( $self->{session} );

	foreach(@tags)
	{
		$values{$_} = &_normalise_string( EPrints::Utils::tree_to_utf8( $field->render_option( $self->{session}, $_ ) ) );
	}

	return \%values;
}

sub _normalise_string
{
	my( $e ) = @_;

	$e =~ s/\s+//g;
	$e = lc($e);
	$e =~ s/(\x{E9}|\x{EA}|\x{E8})/e/g;

	return $e;
}

sub import_documents
{
        my( $self, $eprint, $xml, $is_update ) = @_;

	return if( $is_update );

        my @tef_edition = $xml->getElementsByTagName( 'edition' );
        return undef unless( EPrints::Utils::is_set( @tef_edition ) );

	# the size of the file is how we know we got the right file! see below
	my $filesize = $self->get_node_content( $tef_edition[0], 'extent' );
	return unless( defined $filesize );

	# URL might be: undef, a link to an HTML page (not interested in that) or the URL to the full-text
	# URL might be restricted
	# we'll compare the local file size with the one captured above to make sure we got the right one. Once done, not need to try the other URLs.
	my $urls = $self->get_node_content_multiple( $tef_edition[0], 'identifier', { name => 'xsi:type', value => 'dcterms:URI' } );

	foreach my $url (@$urls)
	{
		next unless( defined $url );
		my $doc = $self->create_document( $url, $eprint );
		next unless( defined $doc );

		my %files = $doc->files;
		if( !defined $files{$doc->get_main} || $files{$doc->get_main} ne "$filesize" )
		{
			my $format = $doc->get_value( 'format' );

			# well if we got a PDF, we'll still keep that one, even if the filesizes mismatch.
			unless( defined $format && $format eq 'application/pdf' )
			{
				print STDERR "\nError filesize mismatch (in xml = $filesize, local = ".$files{$doc->get_main}." )! Removing doc...";
				$doc->remove;
				next;
			}
		}
		last;
	}

}


1;


