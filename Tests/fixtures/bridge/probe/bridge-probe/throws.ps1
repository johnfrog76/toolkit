# Probe: a script that throws -- a terminating error it does not catch, and no reason stated.
$ErrorActionPreference = 'Stop'
throw 'The probe threw: an object at the specified path does not exist.'
