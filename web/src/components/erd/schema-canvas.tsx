"use client";
import { useMemo, useState } from "react";
import { ReactFlow, Handle, Position, Controls, MiniMap, type Node, type NodeProps, type ReactFlowInstance, type Edge } from "@xyflow/react";
import { Button } from "@/components/ui";
import type { SchemaRelation, SchemaTable } from "@/lib/diagrams/manifest";
import "@xyflow/react/dist/style.css";
import "@/styles/erd.css";
type TableNode = Node<{ table: SchemaTable; highlighted: boolean }, "table">;
function TableCard({ data }: NodeProps<TableNode>) { return <div className={`card w-72 rounded-panel border-2 bg-surface p-4 text-foreground ${data.highlighted ? "border-accent" : "border-control"}`}><Handle type="target" position={Position.Left}/><strong className="block text-sm wrap-anywhere">{data.table.name}</strong><p className="my-2 text-xs text-muted">{data.table.status === "proposed" ? "Usulan migration" : "Existing, subset model"}</p><ul className="space-y-2 text-xs">{data.table.columns.map(column => <li key={column.name} className="flex flex-wrap justify-between gap-2"><span className="wrap-anywhere">{column.name}</span><span className="text-muted">{column.type}{column.constraints.includes("PK") ? " · PK" : column.constraints.includes("FK") ? " · FK" : ""}</span></li>)}</ul><Handle type="source" position={Position.Right}/></div>; }
const nodeTypes = { table: TableCard };
export default function SchemaCanvas({ tables, relations, selected, selectedEdge, query, onSelect, onSelectEdge,onClear }: { tables: SchemaTable[]; relations: SchemaRelation[]; selected?: string; selectedEdge?: string; query: string; onSelect: (id: string) => void; onSelectEdge: (id: string) => void;onClear:()=>void }) {
  const [instance, setInstance] = useState<ReactFlowInstance<TableNode, Edge> | null>(null);
  const nodes = useMemo<TableNode[]>(() => tables.map((table, index) => ({ id: table.id, type: "table", position: { x: index % 3 * 390, y: Math.floor(index / 3) * 480 }, data: { table, highlighted: table.id === selected || !!query && `${table.name} ${table.columns.map(column => column.name).join(" ")}`.toLowerCase().includes(query) }, selected: table.id === selected, ariaLabel: `Tabel ${table.name}, ${table.status}, ${table.columns.length} kolom` })), [tables, selected, query]);
  const edges = useMemo<Edge[]>(() => relations.map(relation => ({ id: relation.id, source: relation.source, target: relation.target, type: "smoothstep", selected: relation.id === selectedEdge, label: relation.kind, style: { stroke: relation.id === selectedEdge ? "var(--accent)" : "var(--control)", strokeWidth: 2, strokeDasharray: relation.kind === "FK terdefinisi" ? undefined : "8 5" }, labelStyle: { fill: "var(--fg)", fontSize: 12 }, labelBgStyle: { fill: "var(--surface)" }, ariaLabel: `${relation.label}, ${relation.kind}` })), [relations,selectedEdge]);
  return <>
    <div className="mb-4 flex flex-wrap gap-2">
      <Button onClick={() => instance?.zoomIn()}>Perbesar ERD</Button><Button onClick={() => instance?.zoomOut()}>Perkecil ERD</Button>
      <Button onClick={() => instance?.fitView({ padding: .15, duration: 0 })}>Fit ERD</Button><Button onClick={() => instance?.setViewport({ x: 0, y: 0, zoom: 1 })}>Reset ERD</Button>
    </div>
    <div tabIndex={0} onKeyDownCapture={event=>{if(event.key==='Escape'){event.preventDefault();event.stopPropagation();onClear();}}} className="tt-erd h-152 overflow-hidden rounded-control border border-control bg-canvas">
      <ReactFlow<TableNode> nodes={nodes} edges={edges} nodeTypes={nodeTypes} onInit={setInstance} fitView fitViewOptions={{ padding: .15 }} minZoom={.15} maxZoom={1.7}
        nodesDraggable={false} nodesConnectable={false} deleteKeyCode={null} edgesReconnectable={false}
        onNodeClick={(_, node) => onSelect(node.id)} onEdgeClick={(_, edge) => onSelectEdge(edge.id)}
        onNodesChange={changes => { for (const change of changes) if (change.type === 'select' && change.selected) onSelect(change.id); }}
        onEdgesChange={changes => { for (const change of changes) if (change.type === 'select' && change.selected) onSelectEdge(change.id); }}
        ariaLabelConfig={{ "node.a11yDescription.default": "Tekan Enter untuk memilih tabel. Gunakan Tab untuk berpindah. Diagram baca saja.","node.a11yDescription.keyboardDisabled":"Tekan Enter atau Space untuk memilih tabel. Diagram baca saja.","edge.a11yDescription.default":"Tekan Enter atau Space untuk memilih relasi. Diagram baca saja.", "controls.zoomIn.ariaLabel": "Perbesar diagram", "controls.zoomOut.ariaLabel": "Perkecil diagram", "controls.fitView.ariaLabel": "Sesuaikan diagram" }}>
        <Controls showInteractive={false}/><MiniMap pannable zoomable ariaLabel="Peta mini ERD" nodeColor="var(--panel)" nodeStrokeColor="var(--control)" bgColor="var(--surface)" maskColor="var(--overlay)"/>
      </ReactFlow>
    </div>
  </>;
}
