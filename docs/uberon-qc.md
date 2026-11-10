# Uberon pins and full-Uberon QC

HOMBA pins two things from Uberon, both set in `src/ontology/homba.Makefile`:

```make
HOMBA_BRIDGE_REF = e5f53ebc9e351a5a7c1dfadb49a3f3df05cdf3d8
UBERON_RELEASE = 2026-11-05
```

- **The bridge (`HOMBA_BRIDGE_REF`).** `sources/uberon-bridge-to-homba.owl` is downloaded from this commit of Uberon's `add-homba-bridge` branch (obophenotype/uberon#3681) and merged into `components/all_templates.owl`. The HOMBA bridge isn't in a Uberon release yet, so it is pinned to a commit rather than to `UBERON_RELEASE`. The pinned commit is the human-taxon bridge that the committed component was built from. The branch head has since moved to a mammal-taxon pattern that is still under discussion (obophenotype/uberon#3819).
- **The Uberon release (`UBERON_RELEASE`).** `mirror-uberon` downloads that release's `uberon-base.owl` and removes its disjointness axioms; this becomes part of `imports/merged_import.owl`. `make reason_test_uberon` reasons over `homba-edit.owl` together with that release's **full** `uberon.owl`. Unlike the import, the full release keeps the disjointness axioms, and it is what CL's release reasons with. CI runs the check on every PR.

Pinning means a change on the bridge branch or a new Uberon release can't change HOMBA or fail a PR. They only change when someone deliberately bumps a pin.

## What the check catches

Every mapping in the bridge is an equivalence:

```
HOMBA_x EquivalentTo (UBERON_y and (in_taxon some Homo sapiens))
```

Two kinds of error then show up only when HOMBA is reasoned together with Uberon:

- **Unsatisfiable classes.** A HOMBA structure sits under a parent whose Uberon mapping is a region that Uberon says the structure is *not* in. For example, HOMBA puts the median raphe nucleus in the pontine raphe region (hindbrain), while Uberon puts it in the midbrain reticular formation, and Uberon has *part of midbrain* disjoint with *part of hindbrain*.
- **Inferred equivalences between named classes.** Two HOMBA classes are mapped to the same Uberon class, so they become equivalent to each other, or a HOMBA class becomes equivalent to a Uberon class. CL's release fails on these (`--equivalent-classes-allowed asserted-only`).

The standard `make test` doesn't catch either: the import has no disjointness axioms, and `reason_test` allows inferred equivalences.

## The known-inconsistency list

HOMBA classes that are already inconsistent with full Uberon are listed in `src/ontology/qc_known_inconsistent_full_uberon.txt`. Each line is either the IRI of an unsatisfiable class, or `IRI == IRI` for an inferred equivalence. The header of the list names the Uberon release it was generated for.

`make reason_test_uberon` fails if any of these happen:

| Condition | What to do |
|---|---|
| A class or equivalence that isn't in the list is reported | Fix the mapping that causes it (see "Explaining a reported line" below). Don't add it to the list. |
| A listed line no longer applies | Remove the line from the list in the same PR. A stale line keeps the class exempt, so if it breaks again the check won't notice. |
| The list's header names a different release from `UBERON_RELEASE` | Regenerate the list (see "Bumping a pin" below). |

Rules for the list:

- **Never add a line by hand.** Lines are only added when the list is regenerated during a pin bump, and each new line has to be explained in that PR.
- **Removing lines by hand is fine.** Removing a line is how you record a fix.
- The aim is to shrink the list to nothing. Each fix should remove lines.

## Fixing a listed inconsistency

Where the fix goes depends on what is wrong:

- **A HOMBA mapping is wrong.** Fix it in `src/ontology/bridge/uberon-bridge-to-homba.owl` on Uberon's `add-homba-bridge` branch (the file is hand-made, not generated from `xref:` lines). Reference the HOMBA issue in the commit. The fix reaches HOMBA when `HOMBA_BRIDGE_REF` is bumped to a commit that contains it.
- **A Uberon axiom is wrong.** Fix it in Uberon (`src/ontology/uberon-edit.obo`) and reference the HOMBA issue in the Uberon PR. The fix reaches HOMBA when `UBERON_RELEASE` is bumped to a release that contains it.
- **The HOMBA structure graph is wrong.** Fix it upstream in the HOMBA source; it reaches this repo when the component is rebuilt.

In every case, regenerating the list in the PR that brings the fix in should remove the fixed lines; check that it does, and link the HOMBA issue so it closes. If a fix reaches HOMBA without regenerating the list, remove the fixed lines by hand in the same PR. The check fails until you do.

## Everyday PRs

- **CI checks the committed `components/all_templates.owl` and `imports/merged_import.owl` (`COMP=false`).** It doesn't rebuild the component from the Allen release or download the bridge.
- **To run the check locally:**

  ```sh
  cd src/ontology
  sh run.sh make reason_test_uberon IMP=false PAT=false MIR=false COMP=false
  ```

  The first run downloads the full Uberon file (about 96 MB) to `tmp/uberon-<release>.owl`. Later runs reuse it.

## Explaining a reported line

Unsatisfiable classes:

```sh
cd src/ontology
robot merge -i homba-edit.owl -i tmp/uberon-$(sed -n 's/^UBERON_RELEASE *= *//p' homba.Makefile).owl \
  explain -M unsatisfiability --unsatisfiable all --explanation explain.md
```

Inferred equivalences: look for the Uberon class that both HOMBA classes are mapped to:

```sh
grep -E 'HOMBA_(10577|10578)>' components/all_templates.owl | grep EquivalentClasses
```

## Bumping a pin (before `refresh-imports` and every release)

Pin first, then refresh. This keeps the import, the bridge in the component, and the QC check consistent.

1. Choose the new value:
   - `UBERON_RELEASE`: a release from <https://github.com/obophenotype/uberon/releases>, without the `v`, for example `2026-11-05`. Check that it includes both `uberon-base.owl` and `uberon.owl` as release files.
   - `HOMBA_BRIDGE_REF`: the full SHA of a commit on Uberon's `add-homba-bridge` branch (or of the commit that merged the bridge into Uberon `master`).
2. Set it in `src/ontology/homba.Makefile`.
3. Rebuild the component, which downloads the bridge at `HOMBA_BRIDGE_REF`, and refresh the imports. The component is built twice because the import seed depends on the component, and the component's labels depend on the import:

   ```sh
   sh run.sh make components/all_templates.owl
   sh run.sh make refresh-imports COMP=false
   sh run.sh make components/all_templates.owl
   ```

4. Regenerate the known list:

   ```sh
   sh run.sh make reason_test_uberon IMP=false PAT=false MIR=false COMP=false UBERON_QC_UPDATE=true
   ```

   This rewrites `qc_known_inconsistent_full_uberon.txt` and prints which lines it removed and which it added.
5. Review every added line. Each one is a HOMBA class or equivalence that the new bridge or Uberon release made inconsistent. Explain it, then fix the mapping or open an issue for it, and link the issue in the PR. For each removed line, link the issue it fixes.
6. Open **one PR** with only the pin change, the rebuilt component and imports, and the regenerated list. Don't mix in other changes.
7. Run `make prepare_release` only after that PR is merged.

CI caches the downloaded `uberon.owl` with a cache key based on `UBERON_RELEASE`. Bumping the release downloads the new file once.
