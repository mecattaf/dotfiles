import { render } from '@gpuix/react'
const slots = [1,2,3,4,5,6,7,8,9]
function Rail() {
  return (
    <div style={{ width: 56, height: '100%', backgroundColor: '#000000', display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 12, gap: 2, borderRightWidth: 1, borderColor: '#373735' }}>
      {slots.map(n => (
        <div key={n} style={{ width: 32, height: 30, borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', backgroundColor: n === 3 ? '#171818' : '#000000' }}>
          <text style={{ color: n === 3 ? '#EAECF0' : '#818898', fontFamily: 'Anthropic Sans', fontSize: 13 }}>{String(n)}</text>
        </div>
      ))}
      <div style={{ flexGrow: 1 }} />
      <text style={{ color: '#70B8FF', fontFamily: 'AnthropicMono Nerd Font', fontSize: 11, paddingBottom: 12 }}>23:41</text>
    </div>
  )
}
render(<Rail />, { title: 'gpuix-shell rail probe', appId: 'gpuix-shell-rail', width: 56, height: 900, windowBackground: 'opaque', focus: false,
  layerShell: { namespace: 'gpuix-shell-rail', layer: 'top', anchor: ['left','top','bottom'], exclusiveZone: 56, keyboardInteractivity: 'none' } })
