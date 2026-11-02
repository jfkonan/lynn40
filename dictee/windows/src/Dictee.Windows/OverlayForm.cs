using System.Drawing.Drawing2D;
using Dictee.Core;
using static Dictee.Windows.Native.NativeMethods;

namespace Dictee.Windows;

/// <summary>
/// Pastille flottante en bas au centre de l'écran actif (SPEC.md §6). Elle ne prend jamais le focus
/// (WS_EX_NOACTIVATE, ShowWithoutActivation) et laisse passer les clics (WS_EX_TRANSPARENT).
/// </summary>
internal sealed class OverlayForm : Form
{
    private enum Mode { Hidden, Listening, Transcribing, Message }

    private static readonly Color Background = Color.FromArgb(32, 33, 36);
    private static readonly Color RecordingRed = Color.FromArgb(234, 67, 53);
    private static readonly Color ErrorAmber = Color.FromArgb(251, 188, 4);
    private static readonly Color InfoBlue = Color.FromArgb(138, 180, 248);

    private readonly System.Windows.Forms.Timer _animation = new() { Interval = 40 };
    private readonly System.Windows.Forms.Timer _hideTimer = new();
    private Mode _mode = Mode.Hidden;
    private Func<float>? _levelSource;
    private string _text = "";
    private bool _isError;
    private int _tick;
    private readonly float[] _bars = new float[5];

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        BackColor = Background;
        ForeColor = Color.White;
        Opacity = 0.95; // rend la fenêtre « layered », nécessaire pour que WS_EX_TRANSPARENT laisse passer les clics
        Font = new Font("Segoe UI", 10f, FontStyle.Regular, GraphicsUnit.Point);
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        Text = "Dictée";

        _animation.Tick += (_, _) => { _tick++; Invalidate(); };
        _hideTimer.Tick += (_, _) => HideOverlay();
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            // TopMost passe par WS_EX_TOPMOST plutôt que par la propriété TopMost, dont le SetWindowPos peut activer la fenêtre.
            cp.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_TRANSPARENT;
            return cp;
        }
    }

    public void ShowListening(Func<float> levelSource)
    {
        _levelSource = levelSource;
        Array.Clear(_bars);
        Present(Mode.Listening, "Écoute…", isError: false, autoHide: null);
    }

    public void ShowTranscribing() => Present(Mode.Transcribing, "Transcription…", isError: false, autoHide: null);

    /// <summary>Message temporaire (erreur ou information), affiché environ 4 s.</summary>
    public void ShowMessage(string text, bool isError) =>
        Present(Mode.Message, text, isError, DicteeConstants.ErrorDisplayDuration);

    public void HideOverlay()
    {
        _mode = Mode.Hidden;
        _animation.Stop();
        _hideTimer.Stop();
        _levelSource = null;
        if (Visible) Hide();
    }

    private void Present(Mode mode, string text, bool isError, TimeSpan? autoHide)
    {
        _mode = mode;
        _text = text;
        _isError = isError;
        _tick = 0;
        _hideTimer.Stop();
        if (autoHide is { } delay)
        {
            _hideTimer.Interval = (int)delay.TotalMilliseconds;
            _hideTimer.Start();
        }
        if (mode is Mode.Listening or Mode.Transcribing) _animation.Start(); else _animation.Stop();

        if (!IsHandleCreated) CreateHandle();
        LayoutForScreen();
        if (!Visible) Show();
        // Réaffirme le premier plan sans jamais activer la fenêtre.
        SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        Invalidate();
    }

    /// <summary>Taille selon le texte, position en bas au centre de l'écran de la fenêtre active.</summary>
    private void LayoutForScreen()
    {
        var foreground = GetForegroundWindow();
        var screen = foreground != IntPtr.Zero ? Screen.FromHandle(foreground) : Screen.FromPoint(Cursor.Position);
        var area = screen.WorkingArea;

        int Px(int logical) => LogicalToDeviceUnits(logical);
        var maxTextWidth = Math.Min(Px(560), area.Width - Px(80));
        var textSize = TextRenderer.MeasureText(_text, Font, new Size(maxTextWidth, int.MaxValue),
            TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
        var extra = _mode == Mode.Listening ? Px(44) : 0; // place des barres de niveau
        var width = Px(16) + Px(12) + Px(10) + textSize.Width + extra + Px(18);
        var height = Math.Max(Px(40), textSize.Height + Px(20));

        Bounds = new Rectangle(area.Left + (area.Width - width) / 2, area.Bottom - height - Px(56), width, height);
        UpdateRegion();
    }

    /// <summary>
    /// Passage sur un écran d'une autre échelle : Windows applique sa taille suggérée, mais la région arrondie et le centrage
    /// gardent l'ancienne. On refait la mise en page ; la pastille reste sur le même écran, donc pas de nouveau WM_DPICHANGED.
    /// </summary>
    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e); // met la police à l'échelle et met à jour DeviceDpi
        if (_mode != Mode.Hidden)
        {
            LayoutForScreen();
            Invalidate();
        }
    }

    private void UpdateRegion()
    {
        var radius = Math.Min(Height, LogicalToDeviceUnits(40));
        using var path = RoundedRect(new Rectangle(0, 0, Width, Height), radius);
        var old = Region;
        Region = new Region(path);
        old?.Dispose();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Background);
        int Px(int logical) => LogicalToDeviceUnits(logical);

        // Pastille d'état à gauche.
        var dot = Px(12);
        var dotRect = new Rectangle(Px(16), (Height - dot) / 2, dot, dot);
        switch (_mode)
        {
            case Mode.Listening:
                var pulse = 0.65 + 0.35 * Math.Sin(_tick / 4.0);
                using (var brush = new SolidBrush(Color.FromArgb((int)(255 * pulse), RecordingRed))) g.FillEllipse(brush, dotRect);
                break;
            case Mode.Transcribing:
                using (var pen = new Pen(InfoBlue, Math.Max(2, Px(2))))
                    g.DrawArc(pen, dotRect, (_tick * 24) % 360, 270);
                break;
            default:
                using (var brush = new SolidBrush(_isError ? ErrorAmber : InfoBlue)) g.FillEllipse(brush, dotRect);
                break;
        }

        // Texte.
        var textLeft = dotRect.Right + Px(10);
        var barsWidth = _mode == Mode.Listening ? Px(44) : 0;
        var textRect = new Rectangle(textLeft, 0, Width - textLeft - Px(18) - barsWidth, Height);
        TextRenderer.DrawText(g, _text, Font, textRect, ForeColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);

        // Barres de niveau (écoute).
        if (_mode == Mode.Listening)
        {
            var level = Math.Clamp(_levelSource?.Invoke() ?? 0, 0, 1);
            // Décalage d'un cran à chaque image : petit effet d'onde.
            for (var i = 0; i < _bars.Length - 1; i++) _bars[i] = _bars[i + 1];
            _bars[^1] = level;
            var barWidth = Px(4);
            var gap = Px(3);
            var maxHeight = Height - Px(16);
            var x = Width - Px(18) - (_bars.Length * barWidth + (_bars.Length - 1) * gap);
            using var brush = new SolidBrush(Color.White);
            foreach (var value in _bars)
            {
                var h = Math.Max(barWidth, (int)(maxHeight * value));
                g.FillRectangle(brush, x, (Height - h) / 2, barWidth, h);
                x += barWidth + gap;
            }
        }
    }

    private static GraphicsPath RoundedRect(Rectangle r, int diameter)
    {
        var path = new GraphicsPath();
        path.AddArc(r.Left, r.Top, diameter, diameter, 180, 90);
        path.AddArc(r.Right - diameter, r.Top, diameter, diameter, 270, 90);
        path.AddArc(r.Right - diameter, r.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(r.Left, r.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _animation.Dispose();
            _hideTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
