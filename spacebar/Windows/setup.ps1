Write-Host "TakeItEasy - Spacebar Setup" -ForegroundColor Green
Write-Host ""

$continuationQuestion = Read-Host "Would you like to continue(y/n)"
if ($continuationQuestion -eq "y" -or $continuationQuestion -eq "Y"){
   Clear-Host
   
   Write-Host "Continuing to setup spacebar"
}
elseif ($continuationQuestion -eq "n" or $continuationQuestion -eq "N"){
   Clear-Host
   
   Write-Host "Okay, Thank you!"
   exit 0
}else{
   Clear-Host

   Write-Error "Sorry, that's not an option"
   exit 0
}
