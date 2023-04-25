#!/usr/bin/env nextflow

def helpMessage() {
  log.info"""
  -----------------------------------------------------------------------
                          TUMOUR_ONLY PIPELINE
  -----------------------------------------------------------------------
  Usage:

  nextflow run brucemoran/tumour_only

  Mandatory arguments:

    --outdir        [str]       Path to write output

    --pipeline      [str]       Name of nf-core pipeline as per `nf-core list`

    --revision      [str]       Revision of nf-core pipeline to use

    --email         [str]       Email address to send reports
    """.stripIndent()
}

if (params.help) exit 0, helpMessage()

if(!params.outdir){
    exit 1, "Please include --outdir path for writing to"
}

if(!params.pipeline){
    exit 1, "Please include --pipeline specifying the nf-core pipeline you want"
}

if(!params.revision){
    exit 1, "Please include --revision of the nf-core pipeline you want"
}

if(!params.email){
    exit 1, "Please include --email your@email.com"
}

/*
================================================================================
                          -0. nf-core download
================================================================================
*/
/* 0.00: Download pipeline so we have files to interogate
*/
Channel
  .from(params.pipeline)
  .set { pipe_in }

process Nfcore_download {

  publishDir "${params.outdir}/${params.pipeline}/${params.revision}", mode: "copy"

  input:
  val(pipeline) from pipe_in

  output:
  tuple val(pipeline), file("output/") into sing_pull

  script:
  """
  nf-core download ${pipeline} -r ${params.revision} -o output -c none
  """
}

/*
================================================================================
                          0. Parse modules for Singularity
================================================================================
*/

process Singu_parse {

  publishDir "${params.outdir}/${params.pipeline}/${params.revision}/singularity/", mode: "copy", pattern: "*.[img]"

  input:
  tuple val(pipeline), file(input) from sing_pull

  output:
  file("*.img") into sing_got

  script:
  spd = "singularity_pull_docker_container"
  """
  ##find all main.nf which have the contianer address
  for mains in \$(find ${input}/workflow/modules -name main.nf ); do
    grep -A2 ${spd} ${mains} | cut -d\\' -f2 | tail -n2 > \${mains}.singu
    if [[ \$(grep "depot.galaxyproject" \${mains}.singu | wc -l) > 0 ]]; then
      ##naming
      outname="depot.galaxyproject.org-singularity-"\$(basename \$(grep "depot.galaxyproject" \${mains}.singu) | sed 's/\\:/-/')".img"
      ##getting
      wget -O \${outname} $(grep "depot.galaxyproject" \${mains}.singu)
    elif [[ \$(grep "quay" \${mains}.singu | wc -l) > 0 ]]; then
    fi
  done
  """
}

workflow.onComplete {
  sleep(1000)
  def subject = """\
    [brucemoran/nfcore_download_singularity] SUCCESS [$workflow.runName]
    """
    .stripIndent()
  if (!workflow.success) {
      subject = """\
        [brucemoran/nfcore_download_singularity] FAILURE [$workflow.runName]
        """
        .stripIndent()
  }

  def msg = """\
    Pipeline execution summary
    ---------------------------
    RunName     : ${workflow.runName}
    Completed at: ${workflow.complete}
    Duration    : ${workflow.duration}
    workDir     : ${workflow.workDir}
    exit status : ${workflow.exitStatus}
    """
    .stripIndent()

  sendMail(to: "${params.email}",
           subject: subject,
           body: msg)
}
