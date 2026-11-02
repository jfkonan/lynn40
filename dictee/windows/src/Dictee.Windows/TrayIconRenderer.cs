using System.Drawing.Drawing2D;
using Dictee.Windows.Native;

namespace Dictee.Windows;

/// <summary>Icônes de la zone de notification, dessinées à l'exécution (aucune ressource binaire) : micro blanc sur disque coloré.</summary>
internal static class TrayIconRenderer
{
    public static Color ColorFor(DictationState state) => state switch
    {
        DictationState.Recording => Color.FromArgb(229, 57, 53),     // rouge
        DictationState.Transcribing => Color.FromArgb(30, 136, 229), // bleu
        DictationState.Error => Color.FromArgb(245, 124, 0),         // orange
        _ => Color.FromArgb(84, 90, 99),                             // gris ardoise, lisible sur barre claire ou sombre
    };

    /// <summary>Crée une icône possédée par l'appelant (à libérer avec Dispose).</summary>
    public static Icon Create(DictationState state, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using (var disc = new SolidBrush(ColorFor(state))) g.FillEllipse(disc, 0, 0, size - 1, size - 1);

            float s = size;
            using var white = new SolidBrush(Color.White);
            using var pen = new Pen(Color.White, Math.Max(1.2f, s * 0.08f)) { StartCap = LineCap.Round, EndCap = LineCap.Round };

            // Capsule du micro.
            var capsule = new RectangleF(s * 0.38f, s * 0.17f, s * 0.24f, s * 0.40f);
            using (var path = new GraphicsPath())
            {
                var d = capsule.Width;
                path.AddArc(capsule.Left, capsule.Top, d, d, 180, 180);
                path.AddArc(capsule.Left, capsule.Bottom - d, d, d, 0, 180);
                path.CloseFigure();
                g.FillPath(white, path);
            }
            // Arceau, pied et socle.
            g.DrawArc(pen, s * 0.28f, s * 0.30f, s * 0.44f, s * 0.38f, 0, 180);
            g.DrawLine(pen, s * 0.5f, s * 0.68f, s * 0.5f, s * 0.80f);
            g.DrawLine(pen, s * 0.38f, s * 0.80f, s * 0.62f, s * 0.80f);
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone(); // copie qui possède son handle
        }
        finally
        {
            NativeMethods.DestroyIcon(handle);
        }
    }
}
