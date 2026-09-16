# Local input

Not every bug arrives as an Azure DevOps work item. This file is the supported route for the ones
that do not. Everything after intake is unchanged: the same checkpoint, the same domain selection,
the same implementation, validation and close.

## What counts as local input

| Kind | What it is | What `reference` holds |
|------|------------|------------------------|
| `attached-report` | A report file attached to the request | The path to the saved copy |
| `attached-image` | A screenshot of the wrong result | The path to the saved copy |
| `local-folder` | A project or export folder to reproduce from | The folder path |
| `pasted-symptom` | A symptom typed into the chat, with no file | A short title for the symptom |
| `local-log` | A diagnostic log the person already has | The path to the log |

More than one can arrive together. Record the one the understanding was read from, and record the
rest as evidence.

## Do not run the Azure DevOps intake

There is no work item, so there is nothing to fetch. Do not run `Invoke-EiStoryIntake.ps1`, and do
not write `ado.json`. An absent `ado.json` is correct on this route, not a failure to report.

## Write the understanding

1. Save anything that arrived as a file into the story folder, so it can be read again later.
2. Read it, and write the same understanding you would write from a work item.
3. Compute a hash over the local input and put it in `inputSource.hash`. Take it over the saved
   file when there is one, and over the pasted text when there is not.
4. Fill in `inputSource.kind` and `inputSource.reference` from the table above.
5. Say in `inputSource.adoNotUsedBecause` why Azure DevOps was not used. "No work item exists for
   this report" is a complete answer. "Not checked" is not.
6. Write it with `Write-EiArtifact.ps1 -ArtifactType story-understanding`.

Leave `adoHash` out. The schema asks for `adoHash` or `inputSource`, and refuses a payload that
carries neither.

## Record the input as evidence

Log an `understanding` session entry naming every file you read, with a quote from the report or
the log. A screenshot has no text to quote, so record what you could see in
`attachmentUnderstanding`, and mark anything you inferred rather than read.

## Then carry on as normal

Confirm the understanding with Checkpoint 1. Choose a domain skill with
`Get-EiDomainSkillCatalog.ps1`. Close with `Complete-EiSession.ps1`. A local story is closed the
same way as any other.
