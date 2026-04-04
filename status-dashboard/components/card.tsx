export function Card({
  title,
  fullWidth,
  children,
}: {
  title: string;
  fullWidth?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className={`bg-[#1a1d27] border border-[#2a2e3d] rounded-[10px] p-5 ${
        fullWidth ? "col-span-full" : ""
      }`}
    >
      <h2 className="text-xs uppercase tracking-wider text-[#8b90a0] mb-4">
        {title}
      </h2>
      {children}
    </div>
  );
}
