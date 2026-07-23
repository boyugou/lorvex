use super::super::args::DependencyGraphArgs;
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_dependency_graph(args: DependencyGraphArgs) -> Command {
    let DependencyGraphArgs {
        task_id,
        list_id,
        include_inactive,
        limit_nodes,
        limit_edges,
    } = args;
    Command::Tasks(TasksCommand::DependencyGraph {
        task_id,
        list_id,
        include_inactive,
        limit_nodes,
        limit_edges,
        format: OutputFormat::default(),
    })
}
