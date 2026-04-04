const colors = {
  green: "bg-emerald-400 shadow-[0_0_6px_theme(colors.emerald.400)]",
  red: "bg-red-400 shadow-[0_0_6px_theme(colors.red.400)]",
  yellow: "bg-amber-400 shadow-[0_0_6px_theme(colors.amber.400)]",
};

export function StatusDot({ color }: { color: keyof typeof colors }) {
  return (
    <span
      className={`inline-block w-2 h-2 rounded-full mr-1.5 ${colors[color]}`}
    />
  );
}
