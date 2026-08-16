export default function AppMark({ className = '' }: { className?: string }): React.JSX.Element {
  return <img src="/icon.png" alt="" aria-hidden="true" draggable={false} className={`object-contain ${className}`} />
}
