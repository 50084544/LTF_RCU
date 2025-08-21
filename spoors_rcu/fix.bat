// Fix by replacing problematic rebuilds  
@echo off  
set FILE=lib\features\form\data\models\form_model.dart  
set PATTERN1="() => formKey.currentState?.setState(() {})"  
set REPLACEMENT1="() => (formKey.currentContext as Element?)?.markNeedsBuild()"  
set PATTERN2="(context).markNeedsBuild();"  
set REPLACEMENT2="context.markNeedsBuild();"  
powershell -Command "(Get-Content -Path $FILE) -replace $PATTERN1, $REPLACEMENT1 | Set-Content -Path $FILE"  
powershell -Command "(Get-Content -Path $FILE) -replace $PATTERN2, $REPLACEMENT2 | Set-Content -Path $FILE"  
echo Fixed replacement errors  
