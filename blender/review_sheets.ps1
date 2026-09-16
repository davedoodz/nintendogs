# Assemble existing QA renders for visual inspection; no animation edits.
Add-Type -AssemblyName System.Drawing
$reviewNames = @('pet_head_loop','pet_settle','lie_side_loop','belly_loop','lie_side_up','call_stun','call_curious','paws_up_enter','paws_up_loop','paws_down')
$reviewDirectory = Join-Path $PSScriptRoot 'qa_frames'
$reviewFrameSets = @(@(1,16,41,60),@(1,30,55,90),@(1,40,73,120),@(1,12,34,90),@(1,15,28,45),@(1,2,3,15),@(1,12,30,40),@(1,11,21,30),@(1,19,54,90),@(1,11,21,30))
$reviewClipIndex = 0
foreach ($reviewName in $reviewNames) {
    $reviewFrames = $reviewFrameSets[$reviewClipIndex] | ForEach-Object { Get-Item -LiteralPath (Join-Path $reviewDirectory ('shiba_{0}_{1:000}.png' -f $reviewName,$_)) }
    $reviewClipIndex++
    $reviewCanvas = [System.Drawing.Bitmap]::new(800,710)
    $reviewGraphics = [System.Drawing.Graphics]::FromImage($reviewCanvas)
    $reviewGraphics.Clear([System.Drawing.Color]::White)
    $reviewFont = [System.Drawing.Font]::new('Arial',12)
    $reviewIndex = 0
    foreach ($reviewFrame in $reviewFrames) {
        $reviewImage = [System.Drawing.Image]::FromFile($reviewFrame.FullName)
        $reviewX = ($reviewIndex % 2)*400
        $reviewY = [math]::Floor($reviewIndex / 2)*355
        $reviewGraphics.DrawString($reviewFrame.BaseName,$reviewFont,[System.Drawing.Brushes]::Black,$reviewX,$reviewY)
        $reviewGraphics.DrawImage($reviewImage,$reviewX,($reviewY+25),400,325)
        $reviewImage.Dispose()
        $reviewIndex++
    }
    $reviewCanvas.Save((Join-Path $reviewDirectory "sheet_${reviewName}.png"),[System.Drawing.Imaging.ImageFormat]::Png)
    $reviewFont.Dispose()
    $reviewGraphics.Dispose()
    $reviewCanvas.Dispose()
}
