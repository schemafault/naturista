## Parent

#1

## What to build

Python CLI script that takes Gemma 4 identification JSON (from phase 0.1a), constructs the FLUX prompt per the template, generates an illustration via FLUX schnell quantised MLX, and outputs a PNG. Tests whether local image diffusion produces aesthetically convincing vintage botanical plates.

## FLUX prompt template

```
A botanical illustration of [scientific_name], [common_name], in the style of 19th century natural history plates. [subject_description_from_visible_evidence]. On plain neutral background. No text, no labels, no border.
```

If visible_evidence is sparse, use a conservative generic description rather than fabricating details.

## Acceptance criteria

- [ ] Script accepts Gemma JSON path and photo path as CLI arguments
- [ ] Constructs prompt from scientific_name, common_name, visible_evidence array
- [ ] Loads FLUX schnell quantised MLX
- [ ] Outputs PNG to specified path
- [ ] Run against 5 hand-chosen plants from the common test set
- [ ] Subjective exit criterion: illustrations are recognisably the right plant and aesthetically convincing as 19th-century botanical drawings (judged against Curtis's Botanical Magazine reference plates)
- [ ] If schnell fails the aesthetic bar, retest with FLUX dev-class quantised

## Blocked by

#2 (identification spike must pass first)