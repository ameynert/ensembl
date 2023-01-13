-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2023] EMBL-European Bioinformatics Institute
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

# patch_109_110_c.sql
#
# Title: Allow a gene to belong to multiple alt allele groups
#
# Description:
#   Relax database constraint to allow a given gene id to belong to one or more alt allele groups

ALTER TABLE alt_allele DROP KEY gene_idx;
CREATE INDEX gene_idx ON alt_allele(gene_id);

# patch identifier
INSERT INTO meta (species_id, meta_key, meta_value)
  VALUES (NULL, 'patch', 'patch_109_110_c.sql|Allow gene id to belong to multiple alt allele groups');
