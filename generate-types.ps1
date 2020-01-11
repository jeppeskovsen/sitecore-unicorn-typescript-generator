$FallbackTsType = "unknown"
$OutFile = ".\types.ts"
$UnicornFolder = "..\sitecore-9.3\unicorn"

$TemplateTemplateId = "ab86861a-6030-46c5-b394-e8f99e8b87db"
$StandardTemplateId = "{1930BBEB-7805-471A-A3BE-4858AC7CF696}"
$TemplateFieldId = "455a3e98-a627-4b40-8035-e683a0331ac7"



class TsInterface {
  $_otherInterfaces
  [string] $Id
  [string] $Name
  $Fields
  $BaseTemplates

  TsInterface([System.Object] $TemplateItem, $OtherInterfaces) {
      $this._otherInterfaces = $OtherInterfaces
      $this.Id = $TemplateItem.ID
      $this.Name = $this.FindUniqueName($TemplateItem.Name)
      $this.BaseTemplates = Get-BaseTemplates $TemplateItem
      $this.Fields = Get-TemplateFields $TemplateItem
  }

  $_nameCounter = 0
  [string] FindUniqueName([string] $templateName) {

    if ($this._otherInterfaces.Where({ $_.Name -eq $templateName }, 'First').Count -gt 0) {
        $this._nameCounter++;
        return $this.FindUniqueName("$($templateName)$($this._nameCounter)");
    }

    return $templateName;
  }

  [string] ToTsString() {
    $baseTemplateNames = New-Object System.Collections.Generic.List[string]

    if ($this.BaseTemplates -ne $null -and $this.BaseTemplates.Length -gt 0) {

      foreach($baseTemplateId in $this.BaseTemplates) {
        $smallId = To-SmallId -Id $baseTemplateId
        $baseTsInterfaces = $this._otherInterfaces | Where-Object { $_.Id -eq $smallId }

        if ($baseTsInterfaces -ne $null) {
          foreach ($baseTsInterface in $baseTsInterfaces) {
            $baseTemplateNames.Add((Parse-InterfaceName $baseTsInterface.Name))
          }
        }
      }

    }
    
    return $this.GetTypeScript($baseTemplateNames)
  }


  [string] GetTypeScript($baseTemplateNames) {
    $tsBuilder = [System.Text.StringBuilder]::new()

    if ($baseTemplateNames -ne $null -and $baseTemplateNames.Count -gt 0) {
      [void]$tsBuilder.AppendLine("export interface $($this.Name) extends $([String]::Join(', ', $baseTemplateNames)) {")
    } else {
      [void]$tsBuilder.AppendLine("export interface $($this.Name) {")
    }

    foreach ($field in $this.Fields) {
      $propertyName = Parse-PropertyName $field.Name
      $propertyType = Parse-TsType $field.Type
      [void]$tsBuilder.AppendLine("`t$($propertyName)?: $propertyType;")
    }

    [void]$tsBuilder.AppendLine("}");

    return $tsBuilder.ToString();
  }


}


Function To-SmallId {
  Param (
    [parameter(Mandatory = $true)]
    [string]
    $Id
  )

  if ($Id.StartsWith("{") -and $Id.EndsWith("}")) {
    $Id = $Id.Substring(1)
    $Id = $Id.Substring(0, $Id.Length - 1)
    $Id = $Id.ToLower()
  }

  return $Id
}

Function Parse-TsType
{
  Param (
    [parameter(Mandatory = $true)]
    [System.Object]
    $Type
  )

  switch ($Type.ToLower())
  {
      "single-line text" {
        return "string"
       }
      "number" {
        return "number"
      }
      default {
        return $FallbackTsType
      }
  }
}

Function Parse-InterfaceName {
  Param (
    [parameter(Mandatory = $true)]
    [string]
    $Name
  )

  $Name = $Name.Replace(" ", "")
  return $name;
}

Function Parse-PropertyName {
  Param (
    [parameter(Mandatory = $true)]
    [string]
    $Name
  )

  $Name = $Name.Replace(" ", "")
  return "$($name[0].ToString().ToLower())$($name.Substring(1))"
}

Function Get-TemplateFields {
  Param (
    [parameter(Mandatory = $true)]
    [System.Object]
    $TemplateItem
  )

  $fields = New-Object System.Collections.Generic.List[System.Object]
  $templateFields = Get-UnicornItems -RootPath "$($TemplateItem.DirPath)\$($TemplateItem.Name)" -TemplateId $TemplateFieldId

  foreach ($templateField in $templateFields) {
    $type = Get-FieldValue $templateField -Name "Type"

    $field = @{
      Name = $templateField.Name
      Type = $type
    }

    $fields.Add($field)
  }

  return $fields
}


Function Get-FieldValue {
  Param (
    [parameter(Mandatory = $true)]
    [System.Object]
    $TemplateItem,

    [parameter(Mandatory = $true)]
    [string]
    $Name
  )

  $sharedFields = $TemplateItem.SharedFields
  $fields = $TemplateItem.Fields

  if ($null -eq $sharedFields -and $null -eq $fields) {
    return @()
  }

  $allFields = $sharedFields + $fields

  return $allFields.Where({ $_.Hint -eq $Name }, 'First').Value
}

Function Get-BaseTemplates {
  Param (
    [parameter(Mandatory = $true)]
    [System.Object]
    $TemplateItem
  )

  if ($null -eq $TemplateItem.SharedFields) {
    return @()
  }

  $value = Get-FieldValue $TemplateItem -Name "__Base template"
  if ($null -eq $value) {
    return @()
  }

  return $value.Split([Environment]::NewLine).Where({ $_ -ne "" -and $_ -ne $StandardTemplateId })
}

Function Get-UnicornItems
{
  Param(
    [parameter(Mandatory = $true)]
    [string]
    $RootPath,

    [parameter(Mandatory = $true)]
    [string]
    $TemplateId
  )

  $items = New-Object System.Collections.Generic.List[System.Object]

  $allFiles = Get-ChildItem "$RootPath\**\*.yml" -Recurse

  foreach ($file in $allFiles) {
    Write-Host "Scanning file: " -ForegroundColor Cyan -NoNewline
    Write-Host $file.FullName

    $itemObj = ConvertFrom-Yaml -Yaml ((Get-Content $file.FullName) -Join "`n")
    $template = $itemObj.Template

    if ($template -eq $TemplateId) {
      
      $itemObj.Name = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
      $itemObj.DirPath = [System.IO.Path]::GetDirectoryName($file.FullName)
      $items.Add($itemObj)
    }
  }

  return $items.ToArray()
}


Function Get-TsInterfaces 
{
  Param(
    [parameter(Mandatory = $true)]
    $Templates
  )

  $tsInterfaces = New-Object System.Collections.Generic.List[System.Object]

  foreach ($templateItem in $Templates) {
    $tsInterface =  [TsInterface]::new($templateItem, $tsInterfaces)

    $tsInterfaces.Add($tsInterface)
  }

  return $tsInterfaces
}


$templates = Get-UnicornItems -RootPath $UnicornFolder -TemplateId $TemplateTemplateId
$tsInterfaces = Get-TsInterfaces -Templates $templates


$tsContentsBuilder = [System.Text.StringBuilder]::new()

foreach ($tsInterface in $tsInterfaces) {
  [void]$tsContentsBuilder.Append($tsInterface.ToTsString())
}

$tsContentsBuilder.ToString() | Set-Content $OutFile

Write-Host "Successfully created $OutFile" -ForegroundColor Green