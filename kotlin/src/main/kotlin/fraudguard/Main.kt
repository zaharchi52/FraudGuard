package fraudguard

import fraudguard.ui.FraudGuardFrame
import javax.swing.SwingUtilities
import javax.swing.UIManager

fun main() {
    runCatching { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) }
    SwingUtilities.invokeLater {
        FraudGuardFrame().isVisible = true
    }
}
