export default function Logo({ size = 34, light = true }: { size?: number; light?: boolean }) {
  return (
    <span className="logo" style={{ color: light ? "#F5F2EC" : "#1A1613" }}>
      <svg viewBox="0 0 48 48" width={size} height={size} aria-hidden="true">
        <rect x="0.75" y="0.75" width="46.5" height="46.5" rx="13.5" fill="#1A1613" stroke="#C9A876" strokeOpacity="0.55" strokeWidth="1.5"/><ellipse cx="24" cy="31" rx="17" ry="5.5" fill="none" stroke="#C9A876" strokeWidth="1.6" strokeDasharray="70 8" transform="rotate(-8 24 31)"/><path d="M15 23v11h18V23" fill="none" stroke="#F4ECDC" strokeWidth="2.4" strokeLinejoin="round"/><path d="M10 25 24 12l14 13" fill="none" stroke="#C9A876" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/><rect x="21" y="27" width="6" height="7" rx="1" fill="#C9A876"/>
      </svg>
      <span className="logo-word">
        zaisan<em>fy</em>
      </span>
    </span>
  );
}
