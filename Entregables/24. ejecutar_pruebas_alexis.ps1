param([string]$Servidor = '(localdb)\MSSQLLocalDB')

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$sufijo = [guid]::NewGuid().ToString('N').Substring(0, 10)
$oltp = "Test_Alexis_OLTP_$sufijo"
$mart = "Test_Alexis_Mart_$sufijo"
$evidencia = Join-Path $raiz 'Evidencias_h3\salida_bateria_customer_turned.txt'
$creadoOltp = $false
$creadoMart = $false

function Ejecutar-Sql {
    param([string[]]$Argumentos)
    $salida = & sqlcmd -S $Servidor -E -b -f 65001 -l 20 @Argumentos 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd falló: $($salida -join [Environment]::NewLine)"
    }
    return $salida
}

try {
    Ejecutar-Sql @('-d','master','-Q',"CREATE DATABASE [$oltp]") | Out-Null
    $creadoOltp = $true
    Ejecutar-Sql @('-d','master','-Q',"CREATE DATABASE [$mart]") | Out-Null
    $creadoMart = $true

    Ejecutar-Sql @('-d',$oltp,'-i',(Join-Path $raiz '24. Fixture_OLTP_customer_turned_h3.sql')) | Out-Null
    Ejecutar-Sql @('-d',$oltp,'-i',(Join-Path $raiz '25. Reserva_segura_oltp_h3.sql')) | Out-Null
    Ejecutar-Sql @('-d',$mart,'-i',(Join-Path $raiz '24. Fixture_Mart_customer_turned_h3.sql')) | Out-Null
    Ejecutar-Sql @('-d',$mart,'-v',"OLTP_DB=$oltp",'-i',(Join-Path $raiz '22. Staging_customer_turned_h3.sql')) | Out-Null
    Ejecutar-Sql @('-d',$mart,'-i',(Join-Path $raiz '23. ETL_Fact_AtencionCustomer_h3.sql')) | Out-Null
    Ejecutar-Sql @('-d',$mart,'-i',(Join-Path $raiz '23. ETL_Fact_SeguimientoTurned_h3.sql')) | Out-Null
    $resultado = Ejecutar-Sql @('-d',$mart,'-v',"OLTP_DB=$oltp",'-i',(Join-Path $raiz '24. Pruebas_customer_turned_h3.sql'))

    # Dos sesiones independientes compiten por la misma disponibilidad 9.
    $consulta = 'DECLARE @id INT; EXEC dbo.usp_ReservarTurnoSinColision @IdPersona=2,@IdSolicitud=9,@IdOpcion=9,@IdReserva=@id OUTPUT; SELECT @id AS IdReserva;'
    $trabajos = @(
        (Start-Job -ScriptBlock {
            param($srv,$db,$q)
            $out = & sqlcmd -S $srv -E -b -f 65001 -l 20 -d $db -Q $q 2>&1
            [pscustomobject]@{ Codigo=$LASTEXITCODE; Salida=($out -join ' ') }
        } -ArgumentList $Servidor,$oltp,$consulta),
        (Start-Job -ScriptBlock {
            param($srv,$db,$q)
            $out = & sqlcmd -S $srv -E -b -f 65001 -l 20 -d $db -Q $q 2>&1
            [pscustomobject]@{ Codigo=$LASTEXITCODE; Salida=($out -join ' ') }
        } -ArgumentList $Servidor,$oltp,$consulta)
    )
    $trabajos | Wait-Job | Out-Null
    $resultadosConcurrencia = @($trabajos | Receive-Job)
    $trabajos | Remove-Job
    $ganadores = @($resultadosConcurrencia | Where-Object Codigo -eq 0).Count
    $rechazados = @($resultadosConcurrencia | Where-Object Codigo -ne 0).Count
    $conteo = (Ejecutar-Sql @('-d',$oltp,'-h','-1','-W','-Q',"SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Reservas r JOIN dbo.Opciones o ON o.id_opcion=r.id_opcion WHERE o.id_disponibilidad=9 AND r.estado='Pendiente'")) -join ''
    if ($ganadores -ne 1 -or $rechazados -ne 1 -or $conteo.Trim() -ne '1') {
        throw "Concurrencia incorrecta: exitos=$ganadores, rechazados=$rechazados, filas=$conteo"
    }
    $resultado += 'T13 reserva concurrente: una sesion confirma y la otra recibe conflicto; una sola fila activa: CORRECTO'
    $resultado += 'RESULTADO TOTAL: 13/13 CASOS CORRECTOS'
    $resultado | Set-Content -LiteralPath $evidencia -Encoding utf8
    $resultado
}
finally {
    if ($creadoMart) {
        try { Ejecutar-Sql @('-d','master','-Q',"ALTER DATABASE [$mart] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$mart]") | Out-Null }
        catch { Write-Warning "No se pudo eliminar la base de prueba $mart`: $_" }
    }
    if ($creadoOltp) {
        try { Ejecutar-Sql @('-d','master','-Q',"ALTER DATABASE [$oltp] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$oltp]") | Out-Null }
        catch { Write-Warning "No se pudo eliminar la base de prueba $oltp`: $_" }
    }
}
