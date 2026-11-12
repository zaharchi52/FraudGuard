package fraudguard

<<<<<<< HEAD
import com.formdev.flatlaf.FlatLightLaf
import fraudguard.ui.FraudGuardFrame
import java.awt.Color
=======
import fraudguard.ui.FraudGuardFrame
>>>>>>> 1d3001cacd41e209267ec19f5bcb4072cd6626dd
import javax.swing.SwingUtilities
import javax.swing.UIManager

fun main() {
<<<<<<< HEAD
    runCatching { FlatLightLaf.setup() }
    UIManager.put("Component.arc", 12)
    UIManager.put("Button.arc", 10)
    UIManager.put("TextComponent.arc", 9)
    UIManager.put("ScrollBar.thumbArc", 999)
    UIManager.put("Table.rowHeight", 34)
    UIManager.put("Table.showHorizontalLines", true)
    UIManager.put("Table.showVerticalLines", false)
    UIManager.put("Table.gridColor", Color(0xE8, 0xED, 0xF5))
    UIManager.put("Table.selectionBackground", Color(0xE8, 0xEE, 0xFF))
    UIManager.put("Table.selectionForeground", Color(0x1D, 0x3B, 0x9B))
    UIManager.put("Button.default.background", Color(0x36, 0x5C, 0xF5))
    UIManager.put("Button.default.foreground", Color.WHITE)
    UIManager.put("Component.focusColor", Color(0x72, 0x8D, 0xFF))
    UIManager.put("Panel.background", Color(0xF5, 0xF7, 0xFB))

=======
    runCatching { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) }
>>>>>>> 1d3001cacd41e209267ec19f5bcb4072cd6626dd
    SwingUtilities.invokeLater {
        FraudGuardFrame().isVisible = true
    }
}
