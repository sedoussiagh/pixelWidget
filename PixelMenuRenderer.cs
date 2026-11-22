using System.Drawing;
using System.Windows.Forms;

namespace PixelMonitor
{
    public sealed class MenuRenderer : ToolStripProfessionalRenderer
    {
        public static readonly Color Panel = Color.FromArgb(17, 23, 33);
        private static readonly Color Selection = Color.FromArgb(34, 49, 66);
        private static readonly Color Border = Color.FromArgb(42, 56, 74);
        private static readonly Color Text = Color.FromArgb(232, 239, 249);
        private static readonly Color Muted = Color.FromArgb(126, 145, 169);

        public Color Accent { get; set; }

        public MenuRenderer()
        {
            RoundedEdges = false;
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using (var brush = new SolidBrush(Panel))
                e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderImageMargin(ToolStripRenderEventArgs e)
        {
            using (var brush = new SolidBrush(Panel))
                e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            var size = e.ToolStrip.ClientSize;
            if (size.Width <= 0 || size.Height <= 0) return;
            using (var pen = new Pen(Border))
                e.Graphics.DrawRectangle(pen, 0, 0, size.Width - 1, size.Height - 1);
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (!e.Item.Selected || !e.Item.Enabled) return;
            var area = new Rectangle(Point.Empty, e.Item.Size);
            using (var brush = new SolidBrush(Selection))
                e.Graphics.FillRectangle(brush, area);
            int x = e.Item.RightToLeft == RightToLeft.Yes ? area.Right - 3 : area.Left;
            using (var brush = new SolidBrush(Accent))
                e.Graphics.FillRectangle(brush, x, area.Top, 3, area.Height);
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = !e.Item.Enabled ? Muted : e.Item.Selected ? Accent : Text;
            base.OnRenderItemText(e);
        }

        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            var area = e.ImageRectangle;
            int x = area.Left + (area.Width - 8) / 2;
            int y = area.Top + (area.Height - 8) / 2;
            using (var brush = new SolidBrush(e.Item.Enabled ? Accent : Muted))
            {
                e.Graphics.FillRectangle(brush, x, y, 8, 8);
                e.Graphics.FillRectangle(Brushes.Black, x + 2, y + 3, 2, 2);
                e.Graphics.FillRectangle(Brushes.Black, x + 4, y + 2, 2, 2);
            }
        }

        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = e.Item.Enabled ? Accent : Muted;
            base.OnRenderArrow(e);
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            using (var pen = new Pen(Border))
                e.Graphics.DrawLine(pen, 8, e.Item.Height / 2, e.Item.Width - 8, e.Item.Height / 2);
        }
    }
}
