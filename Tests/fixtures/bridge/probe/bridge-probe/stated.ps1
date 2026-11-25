# Probe: a stated refusal -- Write-CliError, then exit 2 (AGENTS.md, "The refusal contract").
Write-CliError -Message 'The probe card is not in current/.' -Hint 'ProbeOk -Help shows the usage.'
exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
