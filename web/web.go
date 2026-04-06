package web

import (
	"embed"
	"html/template"
	"net/http"
)

//go:embed tmpl/*
var tmplFS embed.FS

var tmpl = template.Must(template.ParseFS(tmplFS, "tmpl/*.html"))

func Run(addr string) {
	http.HandleFunc("/", serveIndex)
	http.HandleFunc("/inbounds", serveView("inbounds"))
	http.HandleFunc("/outbounds", serveView("outbounds"))
	http.HandleFunc("/users", serveView("users"))
	http.HandleFunc("/rules", serveView("rules"))
	http.HandleFunc("/settings", serveView("settings"))
	http.HandleFunc("/logs", serveView("logs"))
	http.HandleFunc("/dashboard", serveView("dashboard"))
	http.ListenAndServe(addr, nil)
}

func serveView(name string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		tmpl.ExecuteTemplate(w, name, nil)
	}
}
