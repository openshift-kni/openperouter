package main

import (
	"flag"
	"fmt"
	"html/template"
	"log"
	"os"
	"path/filepath"
)

type LeafConfig struct {
	NeighborIP         string
	NetworkToAdvertise string
}

func main() {
	var (
		leafName           = flag.String("leaf", "", "Leaf name (e.g., leafA, leafB)")
		neighborIP         = flag.String("neighbor", "", "Neighbor IP address")
		networkToAdvertise = flag.String("network", "", "Network to advertise (CIDR format)")
		outputDir          = flag.String("output", "", "Output directory (default: ../{leaf_name})")
		templateFile       = flag.String("template", "frr.conf.template", "Template file path")
	)
	flag.Parse()

	if *leafName == "" || *neighborIP == "" || *networkToAdvertise == "" {
		fmt.Println("Usage: generate_config -leaf <name> -neighbor <ip> -network <cidr> [options]")
		fmt.Println("Example: generate_config -leaf leafA -neighbor 192.168.1.0 -network 100.64.0.1/32")
		flag.PrintDefaults()
		os.Exit(1)
	}

	if *outputDir == "" {
		*outputDir = filepath.Join("..", *leafName)
	}

	tmplContent, err := os.ReadFile(*templateFile)
	if err != nil {
		log.Fatalf("Error reading template file: %v", err)
	}

	tmpl, err := template.New("frr").Parse(string(tmplContent))
	if err != nil {
		log.Fatalf("Error parsing template: %v", err)
	}

	config := LeafConfig{
		NeighborIP:         *neighborIP,
		NetworkToAdvertise: *networkToAdvertise,
	}

	if err := os.MkdirAll(*outputDir, 0755); err != nil {
		log.Fatalf("Error creating output directory: %v", err)
	}

	outputFile := filepath.Join(*outputDir, "frr.conf")
	file, err := os.Create(outputFile)
	if err != nil {
		log.Fatalf("Error creating output file: %v", err)
	}
	defer file.Close()

	if err := tmpl.Execute(file, config); err != nil {
		log.Fatalf("Error executing template: %v", err)
	}
}
