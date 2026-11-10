## Customize Makefile settings for homba
## 
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile

URIBASE = https://purl.brain-bican.org/ontology

JOBS = HOMBA_v1
BRIDGES = homba
TARGETS = homba

LINKML = linkml-data2owl

STRUCTURE_GRAPHS = $(patsubst %, sources/%.json, $(JOBS))
ALL_GRAPH_ONTOLOGIES = $(patsubst sources/%.json,sources/%.ofn,$(STRUCTURE_GRAPHS))
ALL_BRIDGES = $(patsubst %, sources/uberon-bridge-to-%.owl, $(BRIDGES))
# Keep the template-regenerated bridge workflow disabled until HOMBA has a
# manually curated mapping table to compare against the legacy bridge.
# SOURCE_TEMPLATES = $(patsubst %, ../templates/%_CCF_to_UBERON_source.tsv, $(TARGETS))
# NEW_BRIDGES = $(patsubst %, new-bridges/new-uberon-bridge-to-%.owl, $(TARGETS))


# Rebuilt on every run unless COMP=false (as in QC: `make test COMP=false`), which uses
# the committed component. strip: `COMP=true # comment` in the Makefile leaves a space.
ifeq ($(strip $(COMP)),true)
.PHONY: $(COMPONENTSDIR)/all_templates.owl
$(COMPONENTSDIR)/all_templates.owl: clean_files dependencies $(COMPONENTSDIR)/linkouts.owl $(COMPONENTSDIR)/sources_merged.owl
	$(ROBOT) merge -i $(COMPONENTSDIR)/linkouts.owl -i $(COMPONENTSDIR)/sources_merged.owl annotate --ontology-iri $(URIBASE)/$@ convert -f ofn -o $@
endif
.PRECIOUS: $(COMPONENTSDIR)/all_templates.owl

.PHONY: dependencies
dependencies:
	python3 -m pip install --break-system-packages -r ../../requirements.txt


LOCAL_CLEAN_FILES = $(ALL_GRAPH_ONTOLOGIES) $(ALL_BRIDGES) $(TMPDIR)/tmp.json $(TMPDIR)/tmp.owl $(COMPONENTSDIR)/sources_merged.owl $(COMPONENTSDIR)/linkouts.owl $(TEMPLATEDIR)/linkouts.tsv
# Template-regenerated bridge artifacts to restore later if HOMBA gets a curated mapping workflow:
# LOCAL_CLEAN_FILES += $(SOURCE_TEMPLATES) $(NEW_BRIDGES)

.PHONY: clean_files
clean_files:
	rm -f $(LOCAL_CLEAN_FILES)

sources/HOMBA_v1.json:
	mkdir -p $(dir $@)
	curl -L -o $@ "https://allen-hmba-releases.s3.us-west-2.amazonaws.com/terminology/HOMBA_v1.json"

../linkml/data/template_%.tsv: sources/%.json
	mkdir -p $(dir $@)
	python3 $(SCRIPTSDIR)/structure_graph_template.py -i $< -o $@
.PRECIOUS: ../linkml/data/template_%.tsv

sources/%.ofn: ../linkml/data/template_%.tsv
	$(LINKML) -C Class -s ../linkml/structure_graph_schema.yaml $< -o $@
.PRECIOUS: sources/%.ofn

# The HOMBA bridge isn't in a Uberon release yet (obophenotype/uberon#3681), so it is pinned to a
# commit on Uberon's add-homba-bridge branch instead of the branch head. e5f53ebc is the
# human-taxon bridge that the committed component was built from; the branch head has since moved
# to a mammal-taxon pattern that collapses HOMBA classes onto Uberon (obophenotype/uberon#3819).
# Bump it like UBERON_RELEASE: rebuild the component and regenerate UBERON_QC_KNOWN.
HOMBA_BRIDGE_REF = e5f53ebc9e351a5a7c1dfadb49a3f3df05cdf3d8
sources/uberon-bridge-to-homba.owl:
	mkdir -p $(dir $@)
	curl -fsSL -o $(TMPDIR)/uberon-bridge-to-homba.download.owl "https://raw.githubusercontent.com/obophenotype/uberon/$(HOMBA_BRIDGE_REF)/src/ontology/bridge/uberon-bridge-to-homba.owl"
	python3 $(SCRIPTSDIR)/normalize_homba_bridge_xml.py $(TMPDIR)/uberon-bridge-to-homba.download.owl $@

# Disabled for now: provenance/template regeneration workflow that compares the legacy bridge
# against a manually curated HOMBA mapping table and rebuilds a fresh bridge.
# $(TMPDIR)/%_old_mapping.tsv: sources/uberon-bridge-to-%.owl
# 	$(ROBOT) query --input $< --query ../sparql/bridge_mappings.sparql $@
#
# ../templates/%_CCF_to_UBERON_source.tsv: $(TMPDIR)/%_old_mapping.tsv ../templates/%_CCF_to_UBERON.tsv
# 	python3 ../scripts/mapping_source_template_generator.py -i1 $< -i2 $(word 2, $^) -o $@
# .PRECIOUS: ../templates/%_CCF_to_UBERON_source.tsv
#
# new-bridges/new-uberon-bridge-to-%.owl: ../templates/%_CCF_to_UBERON.tsv ../templates/%_CCF_to_UBERON_source.tsv $(MIRRORDIR)/uberon.owl
# 	mkdir -p $(dir $@)
# 	$(ROBOT) template --input $(MIRRORDIR)/uberon.owl --template $< --output $(TMPDIR)/sourceless-new-uberon-bridge.owl
# 	$(ROBOT) template --input $(MIRRORDIR)/uberon.owl --template $(word 2, $^) --output $(TMPDIR)/CCF_to_UBERON_source.owl
# 	$(ROBOT) merge --input $(TMPDIR)/sourceless-new-uberon-bridge.owl --output $(TMPDIR)/CCF_to_UBERON_source.owl --output $@

$(COMPONENTSDIR)/sources_merged.owl: $(ALL_GRAPH_ONTOLOGIES) $(ALL_BRIDGES)
	$(ROBOT) merge $(patsubst %, -i %, $^) relax annotate --ontology-iri $(URIBASE)/$@ -o $@

$(TMPDIR)/tmp.owl: $(SRC) $(COMPONENTSDIR)/sources_merged.owl
	$(ROBOT) merge $(patsubst %, -i %, $^) relax annotate --ontology-iri $(URIBASE)/$@ -o $@

$(TMPDIR)/tmp.json: $(TMPDIR)/tmp.owl
	$(ROBOT) convert --input $< -f json -o $@

$(TEMPLATEDIR)/linkouts.tsv: $(TMPDIR)/tmp.json
	python3 $(SCRIPTSDIR)/gen_linkout_template.py $<

$(COMPONENTSDIR)/linkouts.owl: $(TMPDIR)/tmp.owl $(TEMPLATEDIR)/linkouts.tsv
	$(ROBOT) template --template $(word 2, $^) --input $< --add-prefixes template_prefixes.json -o $@


# Uberon release used both for the Uberon import (mirror-uberon below) and for the full-Uberon
# QC (reason_test_uberon). Pinned so that a new Uberon release can't change the import or fail
# a PR on its own. Bump it before `make refresh-imports`, then regenerate UBERON_QC_KNOWN with
# `make reason_test_uberon UBERON_QC_UPDATE=true`. See docs/uberon-qc.md.
UBERON_RELEASE = 2026-11-05
UBERON_RELEASE_URL = https://github.com/obophenotype/uberon/releases/download/v$(UBERON_RELEASE)

## ONTOLOGY: uberon (remove disjoint classes and properties to keep merged bridge reasoning tractable)
## Overrides the generated rule, which mirrors the unversioned uberon-base.owl PURL (latest release).
.PHONY: mirror-uberon
.PRECIOUS: $(MIRRORDIR)/uberon.owl
mirror-uberon: | $(TMPDIR)
	if [ $(MIR) = true ] && [ $(IMP) = true ]; then $(ROBOT) convert -I $(UBERON_RELEASE_URL)/uberon-base.owl -o $(TMPDIR)/uberon-download.owl && \
		$(ROBOT) remove -i $(TMPDIR)/uberon-download.owl --axioms disjoint -o $(TMPDIR)/$@.owl; fi


## Disable '--equivalent-classes-allowed asserted-only' due to bridge-level equivalence patterns
.PHONY: reason_test
reason_test: $(EDIT_PREPROCESSED)
	$(ROBOT) reason --input $< --reasoner ELK \
		--exclude-tautologies structural --output test.owl && rm test.owl

## Disable '--equivalent-classes-allowed asserted-only' for the base release
## because HOMBA currently contains inferred equivalent classes.
$(ONT)-base.owl: $(EDIT_PREPROCESSED) $(OTHER_SRC) $(IMPORT_FILES)
	$(ROBOT_RELEASE_IMPORT_MODE) \
	reason --reasoner $(REASONER) --exclude-tautologies structural --annotate-inferred-axioms false \
	relax $(RELAX_OPTIONS) \
	reduce -r $(REASONER) $(REDUCE_OPTIONS) \
	remove --base-iri $(URIBASE)/HOMBA --axioms external --preserve-structure false --trim false \
	$(SHARED_ROBOT_COMMANDS) \
	annotate --link-annotation http://purl.org/dc/elements/1.1/type http://purl.obolibrary.org/obo/IAO_8000001 \
		--ontology-iri $(ONTBASE)/$@ $(ANNOTATE_ONTOLOGY_VERSION) \
		--output $@.tmp.owl && mv $@.tmp.owl $@

$(ONT)-full.owl: $(EDIT_PREPROCESSED) $(OTHER_SRC) $(IMPORT_FILES)
	$(ROBOT_RELEASE_IMPORT_MODE) \
		reason --reasoner ELK --exclude-tautologies structural \
		relax \
		reduce -r ELK \
		$(SHARED_ROBOT_COMMANDS) annotate --ontology-iri $(ONTBASE)/$@ $(ANNOTATE_ONTOLOGY_VERSION) --output $@.tmp.owl && mv $@.tmp.owl $@

$(ONT)-simple.owl: $(EDIT_PREPROCESSED) $(OTHER_SRC) $(SIMPLESEED) $(IMPORT_FILES)
	$(ROBOT_RELEASE_IMPORT_MODE) \
		reason --reasoner ELK --exclude-tautologies structural \
		relax \
		remove --axioms equivalent \
		relax \
		filter --term-file $(SIMPLESEED) --select "annotations ontology anonymous self" --trim true --signature true \
		reduce -r ELK \
		query --update ../sparql/inject-subset-declaration.ru --update ../sparql/inject-synonymtype-declaration.ru \
		$(SHARED_ROBOT_COMMANDS) annotate --ontology-iri $(ONTBASE)/$@ $(ANNOTATE_ONTOLOGY_VERSION) --output $@.tmp.owl && mv $@.tmp.owl $@

$(ONT).owl: $(ONT)-full.owl
	$(ROBOT) annotate --input $< --ontology-iri $(ONTBASE)/$@ $(ANNOTATE_ONTOLOGY_VERSION) \
		convert -o $@.tmp.owl && mv $@.tmp.owl $@

$(ONT).json: $(ONT).owl
	$(ROBOT) annotate --input $< --ontology-iri $(ONTBASE)/$@ $(ANNOTATE_ONTOLOGY_VERSION) \
		convert --check false -f json -o $@.tmp.json && \
		mv $@.tmp.json $@

# QC: reason over HOMBA with the full Uberon release (UBERON_RELEASE), including the disjointness
# axioms that mirror-uberon strips from the import. This is what CL's release sees. Two kinds of
# inconsistency are checked:
#   - unsatisfiable classes, e.g. a HOMBA structure placed under a parent whose Uberon mapping is a
#     region that Uberon says the structure is not in;
#   - inferred equivalences between named classes, e.g. two HOMBA classes mapped to the same Uberon
#     class, which fail CL's `--equivalent-classes-allowed asserted-only`.
# Known ones are listed in UBERON_QC_KNOWN: one IRI per unsatisfiable class, `IRI == IRI` per
# equivalence (IRIs in sorted order). The check fails on anything not in the list, on a listed line that no longer
# applies (remove it from the list), or if the list was generated for another Uberon release.
# Run in CI.
#   make reason_test_uberon UBERON_QC_UPDATE=true   rewrites UBERON_QC_KNOWN and prints what changed
UBERON_QC = $(TMPDIR)/uberon-$(UBERON_RELEASE).owl
UBERON_QC_KNOWN = qc_known_inconsistent_full_uberon.txt
UBERON_QC_UPDATE = false

.PRECIOUS: $(UBERON_QC)
$(UBERON_QC): | $(TMPDIR)
	curl -fsSL --retry 3 -o $@.tmp $(UBERON_RELEASE_URL)/uberon.owl && mv $@.tmp $@

# Unsatisfiable classes stop ROBOT before it reports equivalences, and every unsatisfiable class
# is equivalent to owl:Nothing, so equivalences are found in a second pass without disjointness.
.PHONY: reason_test_uberon
reason_test_uberon: $(EDIT_PREPROCESSED) $(UBERON_QC) | $(TMPDIR)
	$(ROBOT) merge -i $< -i $(UBERON_QC) -o $(TMPDIR)/$@-merged.ofn && \
	$(ROBOT) reason -i $(TMPDIR)/$@-merged.ofn --reasoner ELK --equivalent-classes-allowed all \
		-o $(TMPDIR)/$@.owl > $(TMPDIR)/$@.log 2>&1; status=$$?; \
	grep -oE 'unsatisfiable: [^ ]+' $(TMPDIR)/$@.log | cut -d' ' -f2 > $(TMPDIR)/$@.unsat; \
	if [ $$status -ne 0 ] && [ ! -s $(TMPDIR)/$@.unsat ]; then cat $(TMPDIR)/$@.log; exit 1; fi; \
	$(ROBOT) remove -i $(TMPDIR)/$@-merged.ofn --axioms disjoint \
		reason --reasoner ELK --equivalent-classes-allowed asserted-only \
		-o $(TMPDIR)/$@.owl > $(TMPDIR)/$@-eq.log 2>&1; status=$$?; \
	grep 'Equivalence: ' $(TMPDIR)/$@-eq.log | sed 's/.*Equivalence: //; s/[<>]//g' \
		| awk '{ if ($$1 > $$3) print $$3 " == " $$1; else print $$1 " == " $$3 }' > $(TMPDIR)/$@.equiv; \
	if [ $$status -ne 0 ] && [ ! -s $(TMPDIR)/$@.equiv ]; then cat $(TMPDIR)/$@-eq.log; exit 1; fi; \
	cat $(TMPDIR)/$@.unsat $(TMPDIR)/$@.equiv | LC_ALL=C sort -u > $(TMPDIR)/$@.txt; \
	grep -v '^#' $(UBERON_QC_KNOWN) | LC_ALL=C sort -u > $(TMPDIR)/$@.known; \
	fixed=$$(LC_ALL=C comm -23 $(TMPDIR)/$@.known $(TMPDIR)/$@.txt); \
	new=$$(LC_ALL=C comm -13 $(TMPDIR)/$@.known $(TMPDIR)/$@.txt); \
	if [ $(UBERON_QC_UPDATE) = true ]; then \
		{ echo "# HOMBA inconsistencies with Uberon v$(UBERON_RELEASE) ($(UBERON_RELEASE_URL)/uberon.owl)"; \
		  echo "# One unsatisfiable class per line, or 'IRI == IRI' for an inferred equivalence."; \
		  echo "# Generated by: make reason_test_uberon UBERON_QC_UPDATE=true. Only remove lines by hand. See docs/uberon-qc.md"; \
		  cat $(TMPDIR)/$@.txt; } > $(UBERON_QC_KNOWN); \
		echo "Removed from $(UBERON_QC_KNOWN) (no longer inconsistent): $$(printf '%s' "$$fixed" | grep -c .)"; \
		if [ -n "$$fixed" ]; then echo "$$fixed"; fi; \
		echo "Added to $(UBERON_QC_KNOWN) (new, explain each before committing): $$(printf '%s' "$$new" | grep -c .)"; \
		if [ -n "$$new" ]; then echo "$$new"; fi; \
		echo "Wrote $$(wc -l < $(TMPDIR)/$@.txt | tr -d ' ') lines to $(UBERON_QC_KNOWN)"; exit 0; fi; \
	fail=0; \
	if ! head -1 $(UBERON_QC_KNOWN) | grep -qF "Uberon v$(UBERON_RELEASE) "; then \
		echo "$(UBERON_QC_KNOWN) was not generated for UBERON_RELEASE=$(UBERON_RELEASE)."; \
		echo "Regenerate it: make reason_test_uberon UBERON_QC_UPDATE=true"; fail=1; fi; \
	if [ -n "$$fixed" ]; then echo "No longer inconsistent, remove from $(UBERON_QC_KNOWN):"; echo "$$fixed"; fail=1; fi; \
	if [ -n "$$new" ]; then echo "NEW unsatisfiable classes or inferred equivalences with full Uberon:"; echo "$$new"; \
		echo "Explain with: robot merge -i homba-edit.owl -i $(UBERON_QC) explain -M unsatisfiability --unsatisfiable all --explanation explain.md"; fail=1; fi; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "No new inconsistencies ($$(wc -l < $(TMPDIR)/$@.txt | tr -d ' ') known ones remain, all listed in $(UBERON_QC_KNOWN))"
